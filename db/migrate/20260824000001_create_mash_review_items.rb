# frozen_string_literal: true

class CreateMashReviewItems < ActiveRecord::Migration[7.0]
  def change
    create_table :mash_review_items do |t|
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.bigint :topic_id, null: false
      t.bigint :post_id
      t.bigint :author_id
      t.integer :status, null: false, default: 0
      t.bigint :assigned_to_id
      t.bigint :reviewed_by_id
      t.datetime :reviewed_at
      t.datetime :content_created_at, null: false
      t.boolean :active, null: false, default: true
      t.boolean :legacy, null: false, default: false
      t.integer :notes_count, null: false, default: 0
      t.timestamps
    end

    add_index :mash_review_items, %i[target_type target_id], unique: true
    add_index :mash_review_items, %i[active status content_created_at],
              name: "idx_mash_review_items_queue"
    add_index :mash_review_items, :topic_id
    add_index :mash_review_items, :post_id
    add_index :mash_review_items, :author_id
    add_index :mash_review_items, :assigned_to_id
    add_index :mash_review_items, :reviewed_by_id
  end
end

