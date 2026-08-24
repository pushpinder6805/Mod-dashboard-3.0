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

