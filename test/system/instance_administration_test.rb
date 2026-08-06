# frozen_string_literal: true

# screenote-edition: self_hosted

require_relative "application_system_test_case"
require_relative "../support/instance_administration_test_helper"

class InstanceAdministrationTest < ApplicationSystemTestCase
  include InstanceAdministrationTestHelper
  self.use_transactional_tests = false

  setup do
    skip "run with SCREENOTE_EDITION=self_hosted" unless Screenote::Deployment.current.self_hosted?

    Capybara.reset_sessions!
    @administrator = users(:alice)
    @target = users(:bob)
    prepare_claimed_installation(administrator: @administrator)
    @target.update!(access_status: :active)
    login_as(@administrator.email, "password123")
    click_link "Instance administration"
    assert_selector "h1", text: "Instance administration"
  end

  teardown do
    AuthenticationToken.delete_all
    InstallationAuditEvent.delete_all
    Installation.delete_all
  end

  test "administrator can issue and copy a private recovery link at a narrow viewport" do
    with_playwright_page { |browser_page| browser_page.set_viewport_size(width: 480, height: 720) }

    target_card = find("[data-testid='instance-account']", text: @target.email)
    within(target_card) do
      accept_confirm { click_button "Issue recovery" }
    end

    assert_selector "[data-testid='recovery-link']", wait: 10
    assert_selector "[data-testid='recovery-reveal']", text: "shown only in this response"
    click_button "Copy recovery link"
    assert_selector "[data-clipboard-target='status']:not(:empty)", wait: 5

    geometry = with_playwright_page do |browser_page|
      browser_page.evaluate(<<~JS)
        ({
          viewportWidth: window.innerWidth,
          documentWidth: document.documentElement.scrollWidth,
          overflowers: [...document.querySelectorAll("body *")]
            .map((element) => ({ element, rect: element.getBoundingClientRect() }))
            .filter(({ rect }) => rect.right > window.innerWidth + 1)
            .slice(0, 8)
            .map(({ element, rect }) => ({
              tag: element.tagName,
              className: element.className,
              left: rect.left,
              right: rect.right,
              width: rect.width
            }))
        })
      JS
    end
    assert_operator geometry.fetch("documentWidth"), :<=, geometry.fetch("viewportWidth"), geometry.inspect
  end

  test "suspension invalidates a signed-in account and restore requires a new session" do
    target_session_id = nil
    Capybara.using_session(:signed_in_target) do
      login_as(@target.email, "password123")
      visit dashboard_path
      assert_selector '[data-testid="sign-out-button"]'
      target_session_id = @target.sessions.order(:id).last!.id
    end

    target_card = find("[data-testid='instance-account']", text: @target.email)
    within(target_card) do
      accept_confirm { click_button "Suspend" }
    end
    assert_flash_notice "Account suspended and credentials revoked."
    assert_not Session.exists?(target_session_id)

    Capybara.using_session(:signed_in_target) do
      visit dashboard_path
      assert_current_path new_session_path
      assert_selector "h1", text: "Welcome back"
    end

    target_card = find("[data-testid='instance-account']", text: @target.email)
    within(target_card) do
      accept_confirm { click_button "Restore" }
    end
    assert_flash_notice "Account restored. New sign-in is required."

    Capybara.using_session(:signed_in_target) do
      visit dashboard_path
      assert_current_path new_session_path
      login_as(@target.email, "password123")
      assert_selector '[data-testid="sign-out-button"]'
    end

    assert @target.reload.active?
    assert_not Session.exists?(target_session_id)
  end

  test "a recovery link resets credentials once in a separate browser session" do
    target_card = find("[data-testid='instance-account']", text: @target.email)
    within(target_card) do
      accept_confirm { click_button "Issue recovery" }
    end

    recovery_url = find("[data-testid='recovery-link']").value
    recovery_token = AuthenticationToken.account_recovery.find_by!(user: @target)
    new_password = "new separate-session password"

    Capybara.using_session(:account_recovery) do
      visit_app_url(recovery_url)
      assert_selector "h1", text: "Recover local access"
      assert_empty URI.parse(page.current_url).fragment.to_s
      fill_in "New password", with: new_password
      fill_in "Confirm new password", with: new_password
      click_button "Update password"
      assert_current_path dashboard_path
      assert_flash_notice "Local password updated. Other sessions and credentials were revoked."
    end

    assert_predicate recovery_token.reload, :consumed?
    assert_equal 1, InstallationAuditEvent.where(event_type: "account_recovered", target_user: @target).count

    Capybara.using_session(:replayed_recovery) do
      visit_app_url(recovery_url)
      assert_selector "[role='alert']", text: "This authentication link is invalid or has expired."
      assert_selector "h1", text: "Open secure link"
    end

    Capybara.using_session(:new_credentials) do
      visit new_session_path
      fill_in "Email", with: @target.email
      fill_in "Password", with: "password123"
      click_button "Sign In"
      assert_selector "[role='alert']", text: "Invalid email or password"

      fill_in "Password", with: new_password
      click_button "Sign In"
      assert_current_path dashboard_path
      assert_selector '[data-testid="sign-out-button"]'
    end
  end

  test "transfer removes instance powers from the former administrator immediately" do
    target_card = find("[data-testid='instance-account']", text: @target.email)
    within(target_card) do
      accept_confirm { click_button "Transfer administration" }
    end

    assert_current_path dashboard_path
    assert_no_link "Instance administration"

    visit instance_accounts_path
    assert_current_path dashboard_path
    assert_no_selector "h1", text: "Instance administration"
  end
end
