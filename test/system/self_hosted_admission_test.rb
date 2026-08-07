# frozen_string_literal: true

# screenote-edition: self_hosted

require_relative "application_system_test_case"

class SelfHostedAdmissionTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  setup do
    require_deployment_mode!(:self_hosted)
    Capybara.reset_sessions!
    InstallationAuditEvent.delete_all
    Installation.delete_all
    User.where(email: %w[u8-admin@example.test u8-invitee@example.test]).destroy_all
    @installation = Installations::Prepare.call(deployment: Screenote::Deployment.current)
    assert @installation.unclaimed?, "U8 admission sentinel: installation must start unclaimed"
  end

  teardown do
    AuthenticationToken.delete_all
    InstallationAuditEvent.delete_all
    Installation.delete_all
  end

  test "keyboard bootstrap and no-SMTP invitation create a project-scoped local account" do
    with_playwright_page { |browser_page| browser_page.set_viewport_size(width: 480, height: 720) }
    visit root_path

    assert_selector "h1", text: "Set up Screenote"
    assert_selector "form[action='#{bootstrap_path}']"
    assert_equal "bootstrap_token", page.evaluate_script("document.activeElement.id")
    fill_in "Bootstrap token", with: ENV.fetch("SCREENOTE_BOOTSTRAP_TOKEN")
    fill_in "Email", with: "u8-admin@example.test"
    fill_in "Password", with: "correct horse battery staple"
    fill_in "Confirm password", with: "correct horse battery staple"
    click_button "Create administrator"

    assert_selector "[data-testid='page-title']", text: "Projects"
    click_link "New project"
    fill_in "Name", with: "U8 admission project"
    click_button "Create Project"
    click_link "Members"
    find("input[name='project_invitation[email]']").set("u8-invitee@example.test")
    click_button "Invite"

    link = find("input[id^='invitation-link-']", visible: true).value
    assert_match(%r{\Ahttp://[^/]+/authentication-links/invitation#v1\.}, link)
    assert_not Screenote::Deployment.current.mail?

    Capybara.reset_sessions!
    visit_app_url(link)
    assert_selector "h1", text: "Project invitation"
    fill_in "Create a password", with: "another correct horse battery staple"
    fill_in "Confirm password", with: "another correct horse battery staple"
    click_button "Create account and accept"

    assert_selector "[data-testid='project-detail-title']", text: "U8 admission project"
    visit dashboard_path
    assert_selector "[data-testid='project-card-name']", count: 1, text: /U8 admission project/
  end

  test "retryable link exchange reuses the scrubbed fragment credential from memory" do
    invitation = project_invitations(:pending_invitation)
    issued = issue_invitation_link(invitation)
    exchange_attempts = 0

    with_playwright_page do |browser_page|
      browser_page.route("**/authentication-links/invitation/exchange", lambda do |route, _request|
        exchange_attempts += 1
        if exchange_attempts == 1
          route.fulfill(status: 503, headers: { "Content-Type" => "text/html" }, body: "")
        else
          route.continue
        end
      end)
    end

    visit_app_url(issued.presentation.url)

    assert_selector "[role='alert']", text: /temporarily unable to verify/i
    assert_button "Retry"
    assert_empty URI.parse(page.current_url).fragment.to_s

    click_button "Retry"

    assert_selector "h1", text: "Project invitation"
    assert_equal 2, exchange_attempts
  end

  private

  def issue_invitation_link(invitation)
    ProjectInvitation.transaction do
      AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(
        purpose: :invitation,
        subject: ProjectInvitation.lock.find(invitation.id),
        expires_at: 7.days.from_now
      )
    end
  end
end
