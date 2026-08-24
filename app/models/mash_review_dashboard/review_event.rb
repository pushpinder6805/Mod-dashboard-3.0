# frozen_string_literal: true

module ::MashReviewDashboard
  class ReviewEvent < ActiveRecord::Base
    self.table_name = "mash_review_events"

    belongs_to :review_item,
               class_name: "MashReviewDashboard::ReviewItem",
               inverse_of: :events
    belongs_to :actor, class_name: "User", optional: true

    validates :action, presence: true
  end
end
