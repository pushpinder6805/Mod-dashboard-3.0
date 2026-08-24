# frozen_string_literal: true

module ::MashReviewDashboard
  class Transition
    def self.call(
      item:,
      status:,
      actor:,
      action: "status_changed",
      reason: nil,
      reviewed_at: nil
    )
      new(
        item: item,
        status: status,
        actor: actor,
        action: action,
        reason: reason,
        reviewed_at: reviewed_at
      ).call
    end

    def initialize(item:, status:, actor:, action:, reason:, reviewed_at:)
      @item = item
      @status = status.to_s
      @actor = actor
      @action = action
      @reason = reason.to_s.presence
      @reviewed_at = reviewed_at
    end

    def call
      if !ReviewItem.statuses.key?(@status)
        raise Discourse::InvalidParameters.new(:status)
      end

      from_status = @item.status
      return @item if from_status == @status && @action == "status_changed"

      ReviewItem.transaction do
        attributes = { status: @status }

        if @status == "reviewed"
          attributes[:reviewed_by_id] = @actor&.id
          attributes[:reviewed_at] = @reviewed_at || Time.zone.now
        else
          attributes[:reviewed_by_id] = nil
          attributes[:reviewed_at] = nil
        end

        @item.update!(attributes)
        @item.events.create!(
          action: @action,
          from_status: from_status,
          to_status: @status,
          actor: @actor,
          reason: @reason
        )
      end

      sync_legacy_tag
      @item
    end

    private

    def sync_legacy_tag
      return if !@item.topic_target?
      return if !SiteSetting.tagging_enabled

      topic = @item.topic
      return if topic.blank?

      tag_name = SiteSetting.mash_review_reviewed_tag.to_s.downcase.strip
      return if tag_name.blank?

      tag_names = topic.tags.pluck(:name)
      if @status == "reviewed"
        tag_names << tag_name if !tag_names.include?(tag_name)
      else
        tag_names.delete(tag_name)
      end

      guardian = Guardian.new(@actor || Discourse.system_user)
      DiscourseTagging.tag_topic_by_names(topic, guardian, tag_names.uniq)
    rescue StandardError => error
      Rails.logger.warn(
        "[#{PLUGIN_NAME}] Could not synchronize reviewed tag for topic #{@item.topic_id}: #{error.message}"
      )
    end
  end
end
