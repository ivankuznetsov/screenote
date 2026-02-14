# frozen_string_literal: true

require "test_helper"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get subscription_path
    assert_redirected_to new_session_path
  end

  test "show renders billing page for free user" do
    sign_in(users(:bob))
    get subscription_path
    assert_response :success
    assert_select ".billing-plan__name", "Free"
    assert_select ".billing-plan__name", "Pro"
  end

  test "show displays upgrade button for free user" do
    sign_in(users(:bob))
    get subscription_path
    assert_response :success
    assert_select "button", "Upgrade to Pro"
  end

  test "show displays manage button for pro user" do
    sign_in(users(:alice))
    get subscription_path
    assert_response :success
    assert_select "button", "Manage subscription"
  end

  test "show displays current plan badge" do
    sign_in(users(:bob))
    get subscription_path
    assert_response :success
    assert_select ".billing-plan__badge", "Current plan"
  end
end
