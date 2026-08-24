# frozen_string_literal: true

module ::MashReviewDashboard
  class BaseController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_plugin_enabled
    before_action :ensure_staff

    private

    def ensure_plugin_enabled
      raise Discourse::NotFound if !SiteSetting.mash_review_dashboard_enabled
    end

    def ensure_staff
      raise Discourse::InvalidAccess if !current_user&.staff?
    end

    def user_json(user)
      return nil if user.blank?

      { id: user.id, username: user.username, name: user.name }
    end

    def find_visible_review_item(id)
      item = ReviewItem.find(id)
      guardian.ensure_can_see!(item.topic)
      item
    end
  end
end
