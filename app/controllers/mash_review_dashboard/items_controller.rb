# frozen_string_literal: true

module ::MashReviewDashboard
  class ItemsController < BaseController
    def index
      page = [params.fetch(:page, 1).to_i, 1].max
      per_page = SiteSetting.mash_review_items_per_page
      summary_scope =
        filtered_scope(ReviewItem.in_queue, include_target_type: false)
      scope = filtered_scope(ReviewItem.in_queue, include_target_type: true)
      if ReviewItem.statuses.key?(params[:status].to_s)
        scope = scope.where(status: params[:status])
      end
      total = scope.count
      items =
        scope
          .includes(
            :author,
            :assigned_to,
            :reviewed_by,
            :post,
            topic: :category
          )
          .chronological
          .offset((page - 1) * per_page)
          .limit(per_page)

      render json: {
               items:
                 items.map do |item|
                   ItemPresenter.call(item, guardian: guardian)
                 end,
               counts: status_counts(summary_scope),
               pagination: {
                 page: page,
                 per_page: per_page,
                 total: total,
                 has_more: page * per_page < total
               },
               staff: staff_users,
               migration: migration_state
             }
    end

    def show
      item = find_visible_review_item(params[:id])
      item =
        ReviewItem.includes(
          :topic,
          :post,
          :author,
          :assigned_to,
          :reviewed_by
        ).find(item.id)

      render json: {
               item: ItemPresenter.call(item, guardian: guardian),
               notes:
                 item
                   .notes
                   .includes(:created_by, :updated_by)
                   .order(created_at: :asc)
                   .map { |note| note_json(note) },
               events:
                 item
                   .events
                   .includes(:actor)
                   .order(created_at: :desc)
                   .limit(200)
                   .map { |event| event_json(event) }
             }
    end

    def content
      item = find_visible_review_item(params[:id])
      post = review_post(item)
      guardian.ensure_can_see!(post)

      render json: { content: content_json(item, post) }
    end

    def update_content
      item = find_visible_review_item(params[:id])
      post = review_post(item)
      guardian.ensure_can_edit!(post)

      if params[:original_raw].present? && params[:original_raw] != post.raw
        return render_json_error(I18n.t("edit_conflict"), status: 409)
      end

      changes = {
        raw: params.require(:raw).to_s,
        edit_reason: "Edited from the moderator review dashboard"
      }

      if item.topic_target? && params.key?(:title) &&
           params[:title].to_s.strip != item.topic.title
        guardian.ensure_can_edit_topic!(item.topic)
        changes[:title] = params[:title].to_s.strip
      end

      content_changed = changes[:raw] != post.raw || changes.key?(:title)

      revisor = PostRevisor.new(post, item.topic)
      revisor.revise!(current_user, changes)

      return render_json_error(post) if post.errors.present?
      return render_json_error(item.topic) if item.topic.errors.present?

      post.reload
      item.topic.reload
      if content_changed && SiteSetting.mash_review_reopen_on_edit
        CapturePost.call(post: post, event_name: "edited", actor: current_user)
      end

      render json: {
               content: content_json(item, post),
               item: ItemPresenter.call(item.reload, guardian: guardian)
             }
    end

    def update_status
      item = find_visible_review_item(params[:id])
      status = params.require(:status).to_s

      Transition.call(
        item: item,
        status: status,
        actor: current_user,
        reason: params[:reason]
      )

      render json: { item: ItemPresenter.call(item.reload, guardian: guardian) }
    end

    def update_assignment
      item = find_visible_review_item(params[:id])
      previous_assignee = item.assigned_to
      assignee = find_staff_assignee

      ReviewItem.transaction do
        item.update!(assigned_to: assignee)
        item.events.create!(
          action: assignee.present? ? "assigned" : "unassigned",
          actor: current_user,
          data: {
            previous_assignee_id: previous_assignee&.id,
            assigned_to_id: assignee&.id
          }
        )

        if assignee.present? && item.pending?
          Transition.call(
            item: item,
            status: "in_review",
            actor: current_user,
            action: "claimed_for_review"
          )
        end
      end

      render json: { item: ItemPresenter.call(item.reload, guardian: guardian) }
    end

    private

    def review_post(item)
      post = item.post || item.topic&.first_post
      raise Discourse::NotFound if post.blank?

      post
    end

    def content_json(item, post)
      {
        raw: post.raw,
        cooked: post.cooked,
        title: item.topic.title,
        can_edit: guardian.can_edit?(post),
        can_edit_title:
          item.topic_target? && guardian.can_edit_topic?(item.topic)
      }
    end

    def filtered_scope(scope, include_target_type:)
      scope = visible_to_staff(scope)
      scope =
        scope.where(
          target_type: normalized_target_type
        ) if include_target_type && normalized_target_type.present?
      scope = scope.where(assigned_to_id: params[:assigned_to_id]) if params[
        :assigned_to_id
      ].present?
      scope = scope.where(reviewed_by_id: params[:reviewed_by_id]) if params[
        :reviewed_by_id
      ].present?
      scope = filter_moderator(scope)
      scope = filter_author(scope)
      scope = filter_tags(scope)
      scope = filter_dates(scope)
      scope
    end

    def visible_to_staff(scope)
      scope
        .joins(
          "INNER JOIN topics mash_review_topics ON mash_review_topics.id = mash_review_items.topic_id"
        )
        .joins(
          "LEFT JOIN categories mash_review_categories ON mash_review_categories.id = mash_review_topics.category_id"
        )
        .where(
          "mash_review_topics.category_id IS NULL OR NOT mash_review_categories.read_restricted OR mash_review_topics.category_id IN (:secure_category_ids)",
          secure_category_ids: guardian.secure_category_ids
        )
    end

    def normalized_target_type
      return "Topic" if params[:target_type] == "topic"
      return "Post" if params[:target_type] == "post"

      nil
    end

    def filter_moderator(scope)
      return scope if params[:moderator_id].blank?

      scope.where(
        "mash_review_items.assigned_to_id = :moderator_id OR mash_review_items.reviewed_by_id = :moderator_id",
        moderator_id: params[:moderator_id]
      )
    end

    def filter_author(scope)
      return scope if params[:author].blank?

      username_query = params[:author].to_s.downcase.strip
      user_ids =
        User.where("username_lower LIKE ?", "%#{username_query}%").select(:id)
      scope.where(author_id: user_ids)
    end

    def filter_tags(scope)
      tag_names =
        params[:tags].to_s.split(",").map do |name|
          name.downcase.gsub(/[-_[:space:]]+/, " ").strip
        end.reject(&:blank?).uniq
      return scope if tag_names.empty?

      topic_ids =
        Topic.joins(:tags).where(
          "TRIM(REGEXP_REPLACE(LOWER(tags.name), '[-_[:space:]]+', ' ', 'g')) IN (?)",
          tag_names
        ).select(:id)
      scope.where(topic_id: topic_ids)
    end

    def filter_dates(scope)
      if params[:date_from].present? &&
           (date_from = parse_date(params[:date_from]))
        scope =
          scope.where(
            "mash_review_items.content_created_at >= ?",
            date_from.beginning_of_day
          )
      end

      if params[:date_to].present? && (date_to = parse_date(params[:date_to]))
        scope =
          scope.where(
            "mash_review_items.content_created_at <= ?",
            date_to.end_of_day
          )
      end

      scope
    end

    def parse_date(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def status_counts(scope)
      grouped = scope.group(:target_type, :status).count
      {
        all: grouped.values.sum,
        pending: count_status(grouped, "pending"),
        pending_topics: grouped.fetch(%w[Topic pending], 0),
        pending_posts: grouped.fetch(%w[Post pending], 0),
        in_review: count_status(grouped, "in_review"),
        reviewed: count_status(grouped, "reviewed")
      }
    end

    def count_status(grouped, status)
      grouped.sum do |(_target_type, grouped_status), count|
        grouped_status == status ? count : 0
      end
    end

    def staff_users
      staff_group = Group.find_by(id: Group::AUTO_GROUPS[:staff])
      return [] if staff_group.blank?

      staff_group
        .users
        .where(active: true, staged: false)
        .order(:username_lower)
        .map { |user| user_json(user) }
    end

    def migration_state
      PluginStore.get(PLUGIN_NAME, "legacy_backfill") ||
        { status: "not_started" }
    end

    def find_staff_assignee
      return nil if params[:assigned_to_id].blank?

      user = User.find_by(id: params[:assigned_to_id])
      raise Discourse::InvalidParameters.new(:assigned_to_id) if !user&.staff?

      user
    end

    def note_json(note)
      {
        id: note.id,
        content: note.content,
        created_by: user_json(note.created_by),
        updated_by: user_json(note.updated_by),
        created_at: note.created_at,
        updated_at: note.updated_at
      }
    end

    def event_json(event)
      {
        id: event.id,
        action: event.action,
        from_status: event.from_status,
        to_status: event.to_status,
        reason: event.reason,
        actor: user_json(event.actor),
        data: event.data,
        created_at: event.created_at
      }
    end
  end
end
