# frozen_string_literal: true

module ::Jobs
  class MashReviewCapturePost < ::Jobs::Base
    def execute(args)
      post = Post.find_by(id: args[:post_id])
      return if post.blank?

      MashReviewDashboard::CapturePost.call(post: post, event_name: args[:event].to_s)
    end
  end
end
