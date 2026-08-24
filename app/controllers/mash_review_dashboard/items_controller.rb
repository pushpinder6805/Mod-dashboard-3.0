# frozen_string_literal: true

module ::MashReviewDashboard
  class ItemsController < BaseController
    def index
      page = [params.fetch(:page, 1).to_i, 1].max
      per_page = SiteSetting.mash_review_items_per_page
      unfiltered_status_scope = filtered_scope(ReviewItem.in_queue, include_status: false)
      scope = unfiltered_status_scope
      if ReviewItem.statuses.key?(params[:status].to_s)
        scope = scope.where(status: params[:status])
      end
      total = scope.count
      items =
        scope
          .includes(:author, :assigned_to, :reviewed_by, :post, topic: :category)
          .chronological
          .offset((page - 1) * per_page)
          .limit(per_page)

      render json: {
               items: items.map { |item| ItemPresenter.call(item) },
               counts: status_counts(unfiltered_status_scope),
               pagination: {
                 page: page,
                 per_page: per_page,
                 total: total,
                 has_more: page * per_page < total,
               },
               staff: staff_users,
               categories: categories,
               migration: migration_state,
             }
    end

    def show
      item = find_visible_review_item(params[:id])
      item = ReviewItem.includes(:topic, :post, :author, :assigned_to, :reviewed_by).find(item.id)

      render json: {
               item: ItemPresenter.call(item),
               notes: item.notes.includes(:created_by, :updated_by).order(created_at: :asc).map { |note| note_json(note) },
               events: item.events.includes(:actor).order(created_at: :desc).limit(200).map { |event| event_json(event) },
             }
    end

    def update_status
      item = find_visible_review_item(params[:id])
      status = params.require(:status).to_s

      Transition.call(
        item: item,
        status: status,
        actor: current_user,
        reason: params[:reason],
      )

      render json: { item: ItemPresenter.call(item.reload) }
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
            assigned_to_id: assignee&.id,
          },
        )

        if assignee.present? && item.pending?
          Transition.call(
            item: item,
            status: "in_review",
            actor: current_user,
            action: "claimed_for_review",
          )
        end
      end

      render json: { item: ItemPresenter.call(item.reload) }
    end

    private

    def filtered_scope(scope, include_status:)
      scope = visible_to_staff(scope)
      scope = scope.where(status: params[:status]) if include_status && ReviewItem.statuses.key?(params[:status].to_s)
      scope = scope.where(target_type: normalized_target_type) if normalized_target_type.present?
      scope = scope.where(assigned_to_id: params[:assigned_to_id]) if params[:assigned_to_id].present?
      scope = scope.where(reviewed_by_id: params[:reviewed_by_id]) if params[:reviewed_by_id].present?
      scope = filter_moderator(scope)
      scope = filter_author(scope)
      scope = filter_category(scope)
      scope = filter_dates(scope)
      scope
    end

    def visible_to_staff(scope)
      scope
        .joins("INNER JOIN topics mash_review_topics ON mash_review_topics.id = mash_review_items.topic_id")
        .joins("LEFT JOIN categories mash_review_categories ON mash_review_categories.id = mash_review_topics.category_id")
        .where(
          "mash_review_topics.category_id IS NULL OR NOT mash_review_categories.read_restricted OR mash_review_topics.category_id IN (:secure_category_ids)",
          secure_category_ids: guardian.secure_category_ids,
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
        moderator_id: params[:moderator_id],
      )
    end

    def filter_author(scope)
      return scope if params[:author].blank?

      username_query = params[:author].to_s.downcase.strip
      user_ids = User.where("username_lower LIKE ?", "%#{username_query}%").select(:id)
      scope.where(author_id: user_ids)
    end

    def filter_category(scope)
      return scope if params[:category_id].blank?

      scope.where(topic_id: Topic.where(category_id: params[:category_id]).select(:id))
    end

    def filter_dates(scope)
      if params[:date_from].present? && (date_from = parse_date(params[:date_from]))
        scope = scope.where("mash_review_items.content_created_at >= ?", date_from.beginning_of_day)
      end

      if params[:date_to].present? && (date_to = parse_date(params[:date_to]))
        scope = scope.where("mash_review_items.content_created_at <= ?", date_to.end_of_day)
      end

      scope
    end

    def parse_date(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def status_counts(scope)
      grouped = scope.group(:status).count
      {
        all: grouped.values.sum,
        pending: grouped.fetch(ReviewItem.statuses[:pending], 0),
        in_review: grouped.fetch(ReviewItem.statuses[:in_review], 0),
        reviewed: grouped.fetch(ReviewItem.statuses[:reviewed], 0),
      }
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

    def categories
      Category
        .where(
          "NOT read_restricted OR id IN (:secure_category_ids)",
          secure_category_ids: guardian.secure_category_ids,
        )
        .order(:name)
        .map { |category| { id: category.id, name: category.name, color: category.color } }
    end

    def migration_state
      PluginStore.get(PLUGIN_NAME, "legacy_backfill") || { status: "not_started" }
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
        updated_at: note.updated_at,
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
        created_at: event.created_at,
      }
    end
  end
end
