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

# == Schema Information
#
# Table name: mash_review_events
#
#  id             :bigint           not null, primary key
#  action         :string           not null
#  data           :jsonb            not null
#  from_status    :string
#  reason         :text
#  to_status      :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  actor_id       :bigint
#  review_item_id :bigint           not null
#
# Indexes
#
#  idx_mash_review_events_history        (review_item_id,created_at)
#  index_mash_review_events_on_actor_id  (actor_id)
#
