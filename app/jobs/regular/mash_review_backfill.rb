# frozen_string_literal: true

module ::Jobs
  class MashReviewBackfill < ::Jobs::Base
    def execute(args)
      PluginStore.set(
        MashReviewDashboard::PLUGIN_NAME,
        "legacy_backfill",
        {
          status: "running",
          started_at: Time.zone.now.iso8601,
          actor_id: args[:actor_id]
        }
      )
      actor = User.find_by(id: args[:actor_id]) || Discourse.system_user
      tag_name = SiteSetting.mash_review_reviewed_tag.to_s.downcase.strip
      reviewed_topic_ids = legacy_reviewed_topic_ids(tag_name)

      Topic
        .where(archetype: Archetype.default, deleted_at: nil)
        .find_each do |topic|
          reviewed = reviewed_topic_ids.include?(topic.id)
          capture_topic(topic, reviewed: reviewed, actor: actor)
          capture_replies(topic, reviewed: reviewed, actor: actor)
        end

      PluginStore.set(
        MashReviewDashboard::PLUGIN_NAME,
        "legacy_backfill",
        {
          status: "complete",
          completed_at: Time.zone.now.iso8601,
          actor_id: actor&.id
        }
      )
    rescue StandardError => error
      PluginStore.set(
        MashReviewDashboard::PLUGIN_NAME,
        "legacy_backfill",
        {
          status: "failed",
          failed_at: Time.zone.now.iso8601,
          error: error.message
        }
      )
      raise
    end

    private

    def legacy_reviewed_topic_ids(tag_name)
      return Set.new if tag_name.blank?

      TopicTag
        .joins(:tag)
        .where(tags: { name: tag_name })
        .pluck(:topic_id)
        .to_set
    end

    def capture_topic(topic, reviewed:, actor:)
      first_post = topic.first_post
      return if first_post.blank?

      item =
        MashReviewDashboard::ReviewItem.find_or_initialize_by(
          target_type: "Topic",
          target_id: topic.id
        )
      created = item.new_record?
      item.assign_attributes(
        topic_id: topic.id,
        post_id: first_post.id,
        author_id: first_post.user_id,
        content_created_at: topic.created_at,
        active: true,
        legacy: reviewed
      )
      apply_legacy_status(item, reviewed: reviewed) if created || reviewed
      item.save!
      create_migration_event(item, reviewed: reviewed, actor: actor) if created
    end

    def capture_replies(topic, reviewed:, actor:)
      inherit_reviewed =
        reviewed && SiteSetting.mash_review_legacy_replies_inherit_reviewed

      topic
        .posts
        .where(post_type: Post.types[:regular], deleted_at: nil)
        .where("post_number > 1")
        .find_each do |post|
          item =
            MashReviewDashboard::ReviewItem.find_or_initialize_by(
              target_type: "Post",
              target_id: post.id
            )
          created = item.new_record?
          item.assign_attributes(
            topic_id: topic.id,
            post_id: post.id,
            author_id: post.user_id,
            content_created_at: post.created_at,
            active: true,
            legacy: inherit_reviewed
          )
          if created || inherit_reviewed
            apply_legacy_status(item, reviewed: inherit_reviewed)
          end
          item.save!
          if created
            create_migration_event(
              item,
              reviewed: inherit_reviewed,
              actor: actor
            )
          end
        end
    end

    def apply_legacy_status(item, reviewed:)
      item.status = reviewed ? "reviewed" : "pending"
      item.reviewed_by_id = nil
      item.reviewed_at = nil
    end

    def create_migration_event(item, reviewed:, actor:)
      item.events.create!(
        action: "legacy_migrated",
        to_status: reviewed ? "reviewed" : "pending",
        actor: actor,
        data: {
          source: reviewed ? "reviewed_tag" : "historical_content"
        }
      )
    end
  end
end
