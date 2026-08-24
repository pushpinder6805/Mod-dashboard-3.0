# frozen_string_literal: true

module ::MashReviewDashboard
  class ReviewNote < ActiveRecord::Base
    self.table_name = "mash_review_notes"

    belongs_to :review_item,
               class_name: "MashReviewDashboard::ReviewItem",
               inverse_of: :notes,
               counter_cache: :notes_count
    belongs_to :created_by, class_name: "User"
    belongs_to :updated_by, class_name: "User", optional: true

    validates :content, presence: true, length: { maximum: 10_000 }
  end
end

# == Schema Information
#
# Table name: mash_review_notes
#
#  id             :bigint           not null, primary key
#  content        :text             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  created_by_id  :bigint           not null
#  review_item_id :bigint           not null
#  updated_by_id  :bigint
#
# Indexes
#
#  idx_mash_review_notes_item                (review_item_id,created_at)
#  index_mash_review_notes_on_created_by_id  (created_by_id)
#
