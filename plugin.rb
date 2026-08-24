# frozen_string_literal: true

# name: Mod-dashboard-3.0
# about: A permanent, backend-backed moderator review dashboard for topics and replies.
# version: 1.0.0
# authors: MASH Platform
# url: https://github.com/pushpinder6805/Mod-dashboard-3.0
# required_version: 3.3.0

enabled_site_setting :mash_review_dashboard_enabled

register_asset "stylesheets/common/mash-review-dashboard.scss"

module ::MashReviewDashboard
  DISCOURSE_PLUGIN_NAME = "Mod-dashboard-3.0"
  PLUGIN_NAME = "mash-review-dashboard"
end

require_relative "lib/mash_review_dashboard/engine"

after_initialize do
  on(:post_created) do |post, *_args|
    next if !SiteSetting.mash_review_dashboard_enabled
    next if post.topic&.archetype != Archetype.default

    Jobs.enqueue(:mash_review_capture_post, post_id: post.id, event: "created")
  end

  on(:post_edited) do |post, *_args|
    next if !SiteSetting.mash_review_dashboard_enabled
    next if !SiteSetting.mash_review_reopen_on_edit
    next if post.topic&.archetype != Archetype.default

    Jobs.enqueue(:mash_review_capture_post, post_id: post.id, event: "edited")
  end

  on(:post_destroyed) do |post, *_args|
    next if !SiteSetting.mash_review_dashboard_enabled

    Jobs.enqueue(
      :mash_review_content_state,
      topic_id: post.topic_id,
      post_id: post.id,
      post_number: post.post_number,
      event: "destroyed"
    )
  end

  on(:post_recovered) do |post, *_args|
    next if !SiteSetting.mash_review_dashboard_enabled

    Jobs.enqueue(
      :mash_review_content_state,
      topic_id: post.topic_id,
      post_id: post.id,
      post_number: post.post_number,
      event: "recovered"
    )
  end

  on(:topic_tags_changed) do |topic, payload|
    next if !SiteSetting.mash_review_dashboard_enabled
    next if topic.archetype != Archetype.default

    old_tag_names, new_tag_names, user =
      payload.values_at(:old_tag_names, :new_tag_names, :user)
    reviewed_tag = SiteSetting.mash_review_reviewed_tag.to_s.downcase.strip
    next if reviewed_tag.blank?

    was_reviewed = Array(old_tag_names).include?(reviewed_tag)
    is_reviewed = Array(new_tag_names).include?(reviewed_tag)
    next if was_reviewed == is_reviewed

    Jobs.enqueue(
      :mash_review_sync_legacy_tag,
      topic_id: topic.id,
      reviewed: is_reviewed,
      actor_id: user&.id
    )
  end
end
