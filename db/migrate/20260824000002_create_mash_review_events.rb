# frozen_string_literal: true

class CreateMashReviewEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :mash_review_events do |t|
      t.bigint :review_item_id, null: false
      t.string :action, null: false
      t.string :from_status
      t.string :to_status
      t.bigint :actor_id
      t.text :reason
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end

    add_index :mash_review_events,
              %i[review_item_id created_at],
              name: "idx_mash_review_events_history"
    add_index :mash_review_events, :actor_id
  end
end
