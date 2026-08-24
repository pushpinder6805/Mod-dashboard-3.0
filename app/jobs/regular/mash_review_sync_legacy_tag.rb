# frozen_string_literal: true

module ::Jobs
  class MashReviewSyncLegacyTag < ::Jobs::Base
    def execute(args)
      topic = Topic.find_by(id: args[:topic_id])
      return if topic.blank? || topic.first_post.blank?

      actor = User.find_by(id: args[:actor_id]) || Discourse.system_user
      item =
        MashReviewDashboard::CapturePost.call(
          post: topic.first_post,
          event_name: "legacy_tag_changed",
          actor: actor
        )
      target_status = args[:reviewed] ? "reviewed" : "pending"
      return if item.status == target_status

      MashReviewDashboard::Transition.call(
        item: item,
        status: target_status,
        actor: actor,
        action: args[:reviewed] ? "legacy_tag_added" : "legacy_tag_removed"
      )
    end
  end
end
