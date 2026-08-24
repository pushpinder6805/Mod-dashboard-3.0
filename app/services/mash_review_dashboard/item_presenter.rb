# frozen_string_literal: true

module ::MashReviewDashboard
  class ItemPresenter
    def self.call(item)
      new(item).as_json
    end

    def initialize(item)
      @item = item
    end

    def as_json
      topic = @item.topic
      post = @item.post || topic&.first_post

      {
        id: @item.id,
        target_type: @item.target_type.downcase,
        target_id: @item.target_id,
        topic_id: @item.topic_id,
        post_id: @item.post_id,
        post_number: post&.post_number,
        title: topic&.title || "Deleted topic ##{@item.topic_id}",
        excerpt: post&.excerpt(240, text_entities: true, strip_links: true),
        url: content_url(topic, post),
        category: category_json(topic&.category),
        author: user_json(@item.author),
        status: @item.status,
        is_pending: @item.pending?,
        is_in_review: @item.in_review?,
        is_reviewed: @item.reviewed?,
        assigned_to: user_json(@item.assigned_to),
        reviewed_by: user_json(@item.reviewed_by),
        reviewed_at: @item.reviewed_at,
        content_created_at: @item.content_created_at,
        notes_count: @item.notes_count,
        legacy: @item.legacy,
        active: @item.active,
      }
    end

    private

    def content_url(topic, post)
      return nil if topic.blank?

      post_number = post&.post_number || 1
      "/t/#{topic.slug}/#{topic.id}/#{post_number}"
    end

    def category_json(category)
      return nil if category.blank?

      { id: category.id, name: category.name, color: category.color }
    end

    def user_json(user)
      return nil if user.blank?

      { id: user.id, username: user.username, name: user.name }
    end
  end
end
