# frozen_string_literal: true

require "digest"

module ::MashReviewDashboard
  class MigrationController < BaseController
    MAX_IMPORT_RECORDS = 20_000

    def preview
      tag_name = SiteSetting.mash_review_reviewed_tag.to_s.downcase.strip
      tagged_topic_ids =
        if tag_name.present?
          TopicTag
            .joins(:tag)
            .where(tags: { name: tag_name })
            .distinct
            .pluck(:topic_id)
        else
          []
        end
      reviewed_topic_ids =
        Topic.where(
          id: tagged_topic_ids,
          archetype: Archetype.default,
          deleted_at: nil
        ).pluck(:id)

      reviewed_reply_count =
        if SiteSetting.mash_review_legacy_replies_inherit_reviewed
          Post
            .where(
              topic_id: reviewed_topic_ids,
              post_type: Post.types[:regular],
              deleted_at: nil
            )
            .where("post_number > 1")
            .count
        else
          0
        end

      render json: {
               reviewed_tag: tag_name,
               reviewed_topics: reviewed_topic_ids.length,
               reviewed_replies_to_inherit: reviewed_reply_count,
               historical_topics:
                 Topic.where(
                   archetype: Archetype.default,
                   deleted_at: nil
                 ).count,
               historical_replies:
                 Post
                   .joins(:topic)
                   .where(
                     topics: {
                       archetype: Archetype.default,
                       deleted_at: nil
                     }
                   )
                   .where(post_type: Post.types[:regular], deleted_at: nil)
                   .where("post_number > 1")
                   .count,
               existing_backend_items: ReviewItem.count,
               state:
                 PluginStore.get(PLUGIN_NAME, "legacy_backfill") ||
                   { status: "not_started" }
             }
    end

    def backfill
      state = PluginStore.get(PLUGIN_NAME, "legacy_backfill") || {}
      if %w[queued running].include?(state["status"] || state[:status])
        return render json: { success: true, state: state }
      end

      queued_state = {
        status: "queued",
        queued_at: Time.zone.now.iso8601,
        actor_id: current_user.id
      }
      PluginStore.set(PLUGIN_NAME, "legacy_backfill", queued_state)
      Jobs.enqueue(:mash_review_backfill, actor_id: current_user.id)

      render json: { success: true, state: queued_state }
    end

    def import_local_storage
      records = normalized_records
      if records.length > MAX_IMPORT_RECORDS
        raise Discourse::InvalidParameters.new(:records)
      end

      imported = 0
      skipped = 0

      records.each do |record|
        topic = Topic.find_by(id: record[:topic_id])
        if topic.blank? || topic.archetype != Archetype.default ||
             topic.first_post.blank? || !guardian.can_see?(topic)
          skipped += 1
          next
        end

        import_record(topic, record)
        imported += 1
      rescue ArgumentError, ActiveRecord::RecordInvalid
        skipped += 1
      end

      PluginStore.set(
        PLUGIN_NAME,
        "local_storage_import",
        {
          completed_at: Time.zone.now.iso8601,
          actor_id: current_user.id,
          imported: imported,
          skipped: skipped
        }
      )

      render json: { success: true, imported: imported, skipped: skipped }
    end

    private

    def normalized_records
      raw = params.require(:records)
      records = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw

      if records.is_a?(Hash)
        records.map do |topic_id, metadata|
          metadata = metadata.to_unsafe_h if metadata.respond_to?(:to_unsafe_h)
          symbolize_record(metadata.merge("topic_id" => topic_id))
        end
      else
        Array(records).map do |metadata|
          metadata = metadata.to_unsafe_h if metadata.respond_to?(:to_unsafe_h)
          symbolize_record(metadata)
        end
      end
    end

    def symbolize_record(record)
      {
        topic_id: record["topic_id"] || record[:topic_id],
        username: record["username"] || record[:username],
        reviewed_at:
          record["reviewedAt"] || record[:reviewedAt] ||
            record["reviewed_at"] || record[:reviewed_at],
        comment: record["comment"] || record[:comment]
      }
    end

    def import_record(topic, record)
      reviewer =
        User.find_by(username_lower: record[:username].to_s.downcase) ||
          current_user
      reviewed_at = parse_time(record[:reviewed_at])
      item =
        CapturePost.call(
          post: topic.first_post,
          event_name: "migration",
          actor: reviewer
        )
      import_key =
        Digest::SHA256.hexdigest(
          [
            topic.id,
            record[:username],
            record[:reviewed_at],
            record[:comment]
          ].join("\u0000")
        )
      already_imported =
        item
          .events
          .where(action: "legacy_metadata_imported")
          .where("data ->> 'import_key' = ?", import_key)
          .exists?
      return if already_imported

      ReviewItem.transaction do
        Transition.call(
          item: item,
          status: "reviewed",
          actor: reviewer,
          action: "legacy_metadata_imported",
          reviewed_at: reviewed_at
        )
        item.update!(legacy: true)
        item
          .events
          .order(:id)
          .last
          .update!(
            data: {
              import_key: import_key,
              imported_by_id: current_user.id,
              legacy_username: record[:username].to_s,
              legacy_reviewed_at: record[:reviewed_at].to_s
            }
          )

        comment = record[:comment].to_s.strip
        if comment.present?
          item.notes.find_or_create_by!(content: comment, created_by: reviewer)
        end
      end
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError, TypeError
      nil
    end
  end
end
