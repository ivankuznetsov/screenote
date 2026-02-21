# frozen_string_literal: true

module Pages
  module SubscriptionPage
    # --- Selectors ---

    BILLING_TITLE = '[data-testid="billing-title"]'
    BILLING_PLANS = '[data-testid="billing-plans"]'
    FREE_PLAN = '[data-testid="free-plan"]'
    PRO_PLAN = '[data-testid="pro-plan"]'
    FREE_PLAN_BADGE = '[data-testid="free-plan-badge"]'
    PRO_PLAN_BADGE = '[data-testid="pro-plan-badge"]'
    UPGRADE_BTN = '[data-testid="upgrade-btn"]'
    MANAGE_SUBSCRIPTION_BTN = '[data-testid="manage-subscription-btn"]'
    RENEWAL_DATE = '[data-testid="renewal-date"]'
    CHECKOUT_SUCCESS = '[data-testid="checkout-success"]'
    CHECKOUT_PENDING = '[data-testid="checkout-pending"]'
    CHECKOUT_CANCELED = '[data-testid="checkout-canceled"]'
    BILLING_LINK = '[data-testid="billing-link"]'
    UPGRADE_BANNER = '[data-testid="upgrade-banner"]'

    # --- Actions ---

    def visit_billing
      visit "/subscription"
      assert_selector BILLING_TITLE, wait: 10
    end

    def click_billing_link
      find(BILLING_LINK).click
      assert_selector BILLING_TITLE, wait: 10
    end

    def click_upgrade_to_pro
      find(UPGRADE_BTN).click
    end

    def click_manage_subscription
      find(MANAGE_SUBSCRIPTION_BTN).click
    end

    # --- Assertions ---

    def assert_on_billing_page
      assert_selector BILLING_TITLE, text: "Choose your plan", wait: 10
      assert_selector BILLING_PLANS
    end

    def assert_free_plan_current
      assert_selector FREE_PLAN_BADGE, text: /current/i
      assert_no_selector PRO_PLAN_BADGE
    end

    def assert_pro_plan_current
      assert_selector PRO_PLAN_BADGE, text: /current/i
      assert_no_selector FREE_PLAN_BADGE
    end

    def assert_upgrade_button_visible
      assert_selector UPGRADE_BTN
    end

    def assert_no_upgrade_button
      assert_no_selector UPGRADE_BTN
    end

    def assert_manage_subscription_visible
      assert_selector MANAGE_SUBSCRIPTION_BTN
    end

    def assert_renewal_date_visible
      assert_selector RENEWAL_DATE
    end

    def assert_checkout_success_message
      assert_selector CHECKOUT_SUCCESS, wait: 10
    end

    def assert_checkout_canceled_message
      assert_selector CHECKOUT_CANCELED, wait: 10
    end

    def assert_upgrade_banner_visible
      assert_selector UPGRADE_BANNER
    end

    def assert_no_upgrade_banner
      assert_no_selector UPGRADE_BANNER
    end
  end
end
