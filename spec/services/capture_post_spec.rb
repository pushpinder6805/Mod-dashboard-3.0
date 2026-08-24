# frozen_string_literal: true

require "rails_helper"

RSpec.describe MashReviewDashboard::CapturePost do
  fab!(:user)
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: user) }

  before do
    enable_current_plugin
    SiteSetting.mash_review_dashboard_enabled = true
  end

  it "uses one topic item for the original post and separate items for replies" do
    topic_item = described_class.call(post: first_post)
    reply = Fabricate(:post, topic: topic, user: user)
    reply_item = described_class.call(post: reply)

    expect(topic_item.target_type).to eq("Topic")
    expect(topic_item.target_id).to eq(topic.id)
    expect(reply_item.target_type).to eq("Post")
    expect(reply_item.target_id).to eq(reply.id)
  end

  it "reopens reviewed content after an edit" do
    item = described_class.call(post: first_post)
    MashReviewDashboard::Transition.call(
      item: item,
      status: "reviewed",
      actor: Discourse.system_user,
    )

    described_class.call(post: first_post, event_name: "edited")

    expect(item.reload).to be_pending
    expect(item.events.order(:id).last.action).to eq("content_edited")
  end

  it "is idempotent for repeated post events" do
    2.times { described_class.call(post: first_post) }

    expect(
      MashReviewDashboard::ReviewItem.where(target_type: "Topic", target_id: topic.id).count,
    ).to eq(1)
  end
end
