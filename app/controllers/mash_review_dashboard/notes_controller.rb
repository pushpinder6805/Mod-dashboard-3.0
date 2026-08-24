# frozen_string_literal: true

module ::MashReviewDashboard
  class NotesController < BaseController
    def create
      item = find_visible_review_item(params[:item_id])
      content = params.require(:content).to_s.strip
      raise Discourse::InvalidParameters.new(:content) if content.blank?

      note = nil
      ReviewItem.transaction do
        note = item.notes.create!(content: content, created_by: current_user)
        item.events.create!(
          action: "note_created",
          actor: current_user,
          data: {
            note_id: note.id
          }
        )
      end

      render json: { note: note_json(note) }
    end

    def update
      note = ReviewNote.find(params[:id])
      guardian.ensure_can_see!(note.review_item.topic)
      content = params.require(:content).to_s.strip
      raise Discourse::InvalidParameters.new(:content) if content.blank?

      previous_content = note.content
      ReviewItem.transaction do
        note.update!(content: content, updated_by: current_user)
        note.review_item.events.create!(
          action: "note_edited",
          actor: current_user,
          data: {
            note_id: note.id,
            previous_content: previous_content,
            new_content: content
          }
        )
      end

      render json: { note: note_json(note) }
    end

    private

    def note_json(note)
      {
        id: note.id,
        content: note.content,
        created_by: user_json(note.created_by),
        updated_by: user_json(note.updated_by),
        created_at: note.created_at,
        updated_at: note.updated_at
      }
    end
  end
end
