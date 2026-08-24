# frozen_string_literal: true

module ::Jobs
  class MashReviewContentState < ::Jobs::Base
    def execute(args)
      event_name = args[:event].to_s
      item = find_item(args)
      return if item.blank?

      if event_name == "destroyed"
        item.update!(active: false)
        item.events.create!(action: "content_deleted", actor: Discourse.system_user)
      elsif event_name == "recovered"
        item.update!(active: true)
        MashReviewDashboard::Transition.call(
          item: item,
          status: "pending",
          actor: Discourse.system_user,
          action: "content_recovered",
          reason: "Recovered content requires another review",
        )
      end
    end

    private

    def find_item(args)
      post = Post.find_by(id: args[:post_id])

      post_number = post&.post_number || args[:post_number].to_i

      if post_number == 1
        MashReviewDashboard::ReviewItem.find_by(target_type: "Topic", target_id: args[:topic_id])
      else
        MashReviewDashboard::ReviewItem.find_by(target_type: "Post", target_id: args[:post_id])
      end
    end
  end
end
