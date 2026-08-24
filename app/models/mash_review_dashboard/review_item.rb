# frozen_string_literal: true

module ::MashReviewDashboard
  class ReviewItem < ActiveRecord::Base
    self.table_name = "mash_review_items"

    TARGET_TYPES = %w[Topic Post].freeze

    enum :status, { pending: 0, in_review: 1, reviewed: 2 }

    belongs_to :topic
    belongs_to :post, optional: true
    belongs_to :author, class_name: "User", optional: true
    belongs_to :assigned_to, class_name: "User", optional: true
    belongs_to :reviewed_by, class_name: "User", optional: true

    has_many :events,
             class_name: "MashReviewDashboard::ReviewEvent",
             dependent: :delete_all,
             inverse_of: :review_item
    has_many :notes,
             class_name: "MashReviewDashboard::ReviewNote",
             dependent: :delete_all,
             inverse_of: :review_item

    validates :target_type, inclusion: { in: TARGET_TYPES }
    validates :target_id, :topic_id, :content_created_at, presence: true
    validates :target_id, uniqueness: { scope: :target_type }

    scope :in_queue, -> { where(active: true) }
    scope :chronological, -> { order(content_created_at: :desc, id: :desc) }

    def topic_target?
      target_type == "Topic"
    end
  end
end

