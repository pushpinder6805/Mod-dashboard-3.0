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

# == Schema Information
#
# Table name: mash_review_items
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  content_created_at :datetime         not null
#  legacy             :boolean          default(FALSE), not null
#  notes_count        :integer          default(0), not null
#  reviewed_at        :datetime
#  status             :integer          default("pending"), not null
#  target_type        :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  assigned_to_id     :bigint
#  author_id          :bigint
#  post_id            :bigint
#  reviewed_by_id     :bigint
#  target_id          :bigint           not null
#  topic_id           :bigint           not null
#
# Indexes
#
#  idx_mash_review_items_queue                           (active,status,content_created_at)
#  index_mash_review_items_on_assigned_to_id             (assigned_to_id)
#  index_mash_review_items_on_author_id                  (author_id)
#  index_mash_review_items_on_post_id                    (post_id)
#  index_mash_review_items_on_reviewed_by_id             (reviewed_by_id)
#  index_mash_review_items_on_target_type_and_target_id  (target_type,target_id) UNIQUE
#  index_mash_review_items_on_topic_id                   (topic_id)
#
