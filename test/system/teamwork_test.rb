# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/members_page"

class TeamworkTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::MembersPage

  setup do
    login_as_test_user
  end

  # --- Members page ---

  test "members link visible on project show page" do
    navigate_to_demo_project
    assert_selector "a", text: "Members"
  end

  test "view members page shows owner" do
    navigate_to_demo_project
    click_link "Members"

    assert_on_members_page
    assert_member_listed("test@screenote.app")
    assert_owner_badge_for("test@screenote.app")
  end

  test "owner sees invite form on members page" do
    navigate_to_demo_project
    click_link "Members"

    assert_on_members_page
    assert_invite_form_visible
  end

  # --- Invitations ---

  test "owner can send invitation" do
    project_name = create_unique_project
    click_link "Members"
    assert_on_members_page

    email = "invite-#{Time.now.to_i}@example.com"
    invite_email(email)

    assert_flash_notice "Invitation sent to #{email}."
    assert_pending_invitation(email)
  end

  test "owner can cancel pending invitation" do
    project_name = create_unique_project
    click_link "Members"
    assert_on_members_page

    email = "cancel-#{Time.now.to_i}@example.com"
    invite_email(email)
    assert_flash_notice "Invitation sent to #{email}."
    assert_pending_invitation(email)

    # Cancel the specific invitation by finding its row
    accept_confirm do
      invitation_item = find(MEMBER_ITEM, text: email)
      within(invitation_item) { click_button "Cancel" }
    end

    assert_flash_notice "Invitation cancelled."
  end

  test "invitation rejects duplicate email" do
    project_name = create_unique_project
    click_link "Members"
    assert_on_members_page

    email = "dup-#{Time.now.to_i}@example.com"
    invite_email(email)
    assert_flash_notice "Invitation sent to #{email}."

    invite_email(email)
    assert_selector ".flash--alert", text: /already been invited/i, wait: 10
  end

  test "invitation rejects existing member email" do
    navigate_to_demo_project
    click_link "Members"
    assert_on_members_page

    invite_email("test@screenote.app")
    assert_selector ".flash--alert", text: /already a member/i, wait: 10
  end

  # --- Owner-only actions ---

  test "owner sees edit and delete buttons on project show" do
    navigate_to_demo_project

    assert_selector "a", text: "Edit"
    assert_selector "button", text: "Delete"
    assert_selector "a", text: "API keys"
  end

  # --- Invitation shows as pending ---

  test "sent invitation appears in pending list" do
    project_name = create_unique_project
    click_link "Members"
    assert_on_members_page

    email = "pending-#{Time.now.to_i}@example.com"
    invite_email(email)
    assert_flash_notice "Invitation sent to #{email}."

    # Verify invitation is visible in pending section
    assert_pending_invitation(email)

    # Verify it shows the "Invited X ago" label
    assert_selector PENDING_LABEL, wait: 5
  end

  # --- Back navigation ---

  test "back link on members page returns to project" do
    navigate_to_demo_project
    click_link "Members"
    assert_on_members_page

    click_link "← Back to project"
    assert_on_project_show("Demo Project")
  end

  # --- Team count ---

  test "members page shows team count" do
    navigate_to_demo_project
    click_link "Members"

    assert_selector SECTION_TITLE, text: /Team \(\d+\)/
  end

  private

  def create_unique_project
    name = "Teamwork #{Time.now.to_i}"
    visit_new_project
    fill_project_form(name: name)
    submit_project_form
    assert_on_project_show(name)
    name
  end
end
