# frozen_string_literal: true

module ::MashReviewDashboard
  class CapturePost
    def self.call(post:, event_name: "created", actor: nil)
      new(post: post, event_name: event_name, actor: actor).call
    end

    def initialize(post:, event_name:, actor:)
      @post = post
      @event_name = event_name
      @actor = actor || Discourse.system_user
    end

    def call
      return if @post.blank? || @post.topic.blank?
      return if @post.topic.archetype != Archetype.default
      return if @post.post_type != Post.types[:regular]

      target_type = @post.post_number == 1 ? "Topic" : "Post"
      target_id = target_type == "Topic" ? @post.topic_id : @post.id
      item = ReviewItem.find_or_initialize_by(target_type: target_type, target_id: target_id)
      created = item.new_record?

      item.assign_attributes(
        topic_id: @post.topic_id,
        post_id: @post.id,
        author_id: @post.user_id,
        content_created_at: @post.created_at,
        active: @post.deleted_at.blank? && @post.topic.deleted_at.blank?,
      )
      item.save!

      if created
        item.events.create!(action: "content_created", actor: @actor)
      elsif @event_name == "edited" && item.reviewed?
        Transition.call(
          item: item,
          status: "pending",
          actor: @actor,
          action: "content_edited",
          reason: "Content changed after it was reviewed",
        )
      elsif @event_name == "recovered"
        item.update!(active: true)
        item.events.create!(action: "content_recovered", actor: @actor)
      end

      item
    end
  end
end
