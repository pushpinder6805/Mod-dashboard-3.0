# frozen_string_literal: true

class CreateMashReviewNotes < ActiveRecord::Migration[7.0]
  def change
    create_table :mash_review_notes do |t|
      t.bigint :review_item_id, null: false
      t.bigint :created_by_id, null: false
      t.bigint :updated_by_id
      t.text :content, null: false
      t.timestamps
    end

    add_index :mash_review_notes, %i[review_item_id created_at],
              name: "idx_mash_review_notes_item"
    add_index :mash_review_notes, :created_by_id
  end
end
