# frozen_string_literal: true

require "rails_helper"

describe MashReviewDashboard::ItemsController do
  fab!(:admin)
  fab!(:moderator)
  fab!(:user)
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: user) }

  before do
    enable_current_plugin
    SiteSetting.mash_review_dashboard_enabled = true
  end

  describe "GET /mash-review-dashboard/items.json" do
    it "is staff-only" do
      MashReviewDashboard::CapturePost.call(post: first_post)
      sign_in(user)

      get "/mash-review-dashboard/items.json"

      expect(response.status).to eq(403)
    end

    it "returns permanent topic and reply records to staff" do
      topic_item = MashReviewDashboard::CapturePost.call(post: first_post)
      reply = Fabricate(:post, topic: topic, user: user)
      reply_item = MashReviewDashboard::CapturePost.call(post: reply)
      sign_in(moderator)

      get "/mash-review-dashboard/items.json", params: { status: "pending" }

      expect(response.status).to eq(200)
      expect(
        response.parsed_body["items"].map { |item| item["id"] }
      ).to contain_exactly(topic_item.id, reply_item.id)
      expect(response.parsed_body.dig("counts", "pending")).to eq(2)
      expect(response.parsed_body.dig("counts", "pending_topics")).to eq(1)
      expect(response.parsed_body.dig("counts", "pending_posts")).to eq(1)

      get "/mash-review-dashboard/items.json",
          params: {
            status: "pending",
            target_type: "topic"
          }

      expect(response.parsed_body["items"].pluck("id")).to eq([topic_item.id])
      expect(response.parsed_body.dig("counts", "pending_posts")).to eq(1)
    end
  end

  describe "PUT /mash-review-dashboard/items/:id/status.json" do
    it "persists review and unreview transitions with history" do
      item = MashReviewDashboard::CapturePost.call(post: first_post)
      sign_in(moderator)

      put "/mash-review-dashboard/items/#{item.id}/status.json",
          params: {
            status: "reviewed"
          }
      expect(response.status).to eq(200)
      expect(item.reload).to be_reviewed
      expect(item.reviewed_by).to eq(moderator)

      put "/mash-review-dashboard/items/#{item.id}/status.json",
          params: {
            status: "pending",
            reason: "Needs a second review"
          }
      expect(response.status).to eq(200)
      expect(item.reload).to be_pending
      expect(item.events.order(:id).last.reason).to eq("Needs a second review")
      expect(item.events.where(to_status: "reviewed")).to exist
    end
  end

  describe "PUT /mash-review-dashboard/items/:id/assignment.json" do
    it "assigns a moderator and moves a pending item into review" do
      item = MashReviewDashboard::CapturePost.call(post: first_post)
      sign_in(admin)

      put "/mash-review-dashboard/items/#{item.id}/assignment.json",
          params: {
            assigned_to_id: moderator.id
          }

      expect(response.status).to eq(200)
      expect(item.reload.assigned_to).to eq(moderator)
      expect(item).to be_in_review
    end
  end
end

describe MashReviewDashboard::NotesController do
  fab!(:moderator)
  fab!(:user)
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: user) }

  before do
    enable_current_plugin
    SiteSetting.mash_review_dashboard_enabled = true
  end

  it "creates and edits staff-only notes while retaining edit history" do
    item = MashReviewDashboard::CapturePost.call(post: first_post)
    sign_in(moderator)

    post "/mash-review-dashboard/items/#{item.id}/notes.json",
         params: {
           content: "Checking this with the policy team."
         }
    expect(response.status).to eq(200)
    note_id = response.parsed_body.dig("note", "id")

    put "/mash-review-dashboard/notes/#{note_id}.json",
        params: {
          content: "Policy team confirmed this is correct."
        }
    expect(response.status).to eq(200)

    note = MashReviewDashboard::ReviewNote.find(note_id)
    expect(note.content).to eq("Policy team confirmed this is correct.")
    edit_event = item.events.find_by(action: "note_edited")
    expect(edit_event.data["previous_content"]).to eq(
      "Checking this with the policy team."
    )
  end
end
