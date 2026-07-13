# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/subscription_page"
require "ostruct"

class SubscriptionsFreeUserTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::SubscriptionPage

  setup do
    login_as("free@screenote.app", "password")
  end

  test "free user billing page shows free as current plan" do
    visit_billing

    assert_on_billing_page
    assert_free_plan_current
    assert_upgrade_button_visible
  end

  test "free user billing page shows correct pricing" do
    visit_billing

    assert_selector PRO_PLAN, text: "$10"
    assert_selector FREE_PLAN, text: "$0"
  end

  test "free user billing page shows plan features" do
    visit_billing

    within(FREE_PLAN) do
      assert_text "1 project"
      assert_text "1 team member"
      assert_text "Screenote CLI access"
      assert_text "OAuth CLI sign-in and direct API automation"
    end

    within(PRO_PLAN) do
      assert_text "Everything in Free"
      assert_text "Unlimited projects"
      assert_text "Unlimited team members"
    end
  end

  test "clicking upgrade redirects to Stripe Checkout" do
    visit_billing

    original_create = Stripe::Checkout::Session.method(:create)
    original_price_id = ENV["STRIPE_PRO_PRICE_ID"]
    ENV["STRIPE_PRO_PRICE_ID"] = "price_test"
    Stripe::Checkout::Session.define_singleton_method(:create) do |*_args|
      OpenStruct.new(url: "https://checkout.stripe.com/c/test_session")
    end

    begin
      with_playwright_page do |pw_page|
        pw_page.expect_navigation(url: /checkout\.stripe\.com/, timeout: 30_000) do
          pw_page.locator('[data-testid="upgrade-btn"]').click
        end
        assert pw_page.url.include?("checkout.stripe.com"), "Expected redirect to Stripe Checkout, got: #{pw_page.url}"
      end
    ensure
      Stripe::Checkout::Session.define_singleton_method(:create, original_create)
      ENV["STRIPE_PRO_PRICE_ID"] = original_price_id
    end
  end

  test "canceled checkout shows canceled message" do
    visit "/subscription?status=canceled"
    assert_selector BILLING_TITLE, wait: 10

    assert_checkout_canceled_message
  end
end

class SubscriptionsProUserTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::SubscriptionPage

  setup do
    login_as_test_user
  end

  test "pro user billing page shows pro as current plan" do
    visit_billing

    assert_on_billing_page
    assert_pro_plan_current
    assert_manage_subscription_visible
    assert_renewal_date_visible
  end

  test "pro user does not see upgrade button" do
    visit_billing

    assert_no_upgrade_button
  end

  test "pro user projects page does not show upgrade banner" do
    visit_projects

    assert_no_upgrade_banner
  end
end

class SubscriptionsNavigationTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::SubscriptionPage

  setup do
    login_as_test_user
  end

  test "billing link in header navigates to billing page" do
    visit_projects
    click_billing_link

    assert_on_billing_page
  end

  test "back link on billing page returns to projects" do
    visit_billing
    click_link "← Back to projects"

    assert_on_projects_index
  end
end
