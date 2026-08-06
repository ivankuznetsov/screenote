# frozen_string_literal: true

require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @non_admin = users(:alice)
  end

  test "redirects to sign in when not authenticated" do
    get admin_dashboard_path
    assert_redirected_to new_session_path
  end

  test "redirects non-admin users to dashboard" do
    sign_in(@non_admin)
    get admin_dashboard_path
    assert_redirected_to dashboard_path
    assert_equal "Not authorized.", flash[:alert]
  end

  test "returns not found when the admin route is exposed without the SaaS capability" do
    sign_in(@admin)
    deployment = Struct.new(:saas?, :billing?).new(false, false)
    original = Screenote::Deployment.method(:current)
    Screenote::Deployment.define_singleton_method(:current) { deployment }

    get admin_dashboard_path

    assert_response :not_found
  ensure
    Screenote::Deployment.define_singleton_method(:current, original) if original
  end

  test "shows dashboard for admin user" do
    sign_in(@admin)
    get admin_dashboard_path
    assert_response :success
    assert_select ".admin-stats__value", count: 3
  end

  test "displays verified users count" do
    sign_in(@admin)
    get admin_dashboard_path
    assert_response :success
    verified_count = User.where.not(confirmed_at: nil).count
    assert_select "[data-testid='verified-users-count']", text: verified_count.to_s
  end

  test "displays pro users count" do
    sign_in(@admin)
    get admin_dashboard_path
    assert_response :success
    pro_count = Subscription.where(plan: :pro, status: :active)
      .where("current_period_end > ?", Time.current).count
    assert_select "[data-testid='pro-users-count']", text: pro_count.to_s
  end

  test "displays users with content count" do
    sign_in(@admin)
    get admin_dashboard_path
    assert_response :success
    content_count = User.joins(owned_projects: :screenshots).distinct.count
    assert_select "[data-testid='users-with-content-count']", text: content_count.to_s
  end
end
