# frozen_string_literal: true

module Admin
  class DashboardController < ApplicationController
    before_action :require_admin!

    def show
      @verified_users_count = User.where.not(confirmed_at: nil).count
      @users_with_projects_and_screenshots_count = User
        .joins(owned_projects: :screenshots)
        .distinct
        .count
      @pro_users_count = Subscription.where(plan: :pro, status: :active)
        .where("current_period_end > ?", Time.current)
        .count
    end

    private

    def require_admin!
      return if Current.user&.admin?

      redirect_to dashboard_path, alert: "Not authorized."
    end
  end
end
