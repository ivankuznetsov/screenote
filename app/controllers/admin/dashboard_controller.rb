# frozen_string_literal: true

module Admin
  class DashboardController < ApplicationController
    before_action :require_saas_operator!

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

    def require_saas_operator!
      return not_found unless Screenote::Deployment.current.saas?
      return if Current.user.saas_operator?

      redirect_to dashboard_path, alert: "Not authorized."
    end
  end
end
