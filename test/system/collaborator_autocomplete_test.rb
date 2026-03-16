# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/members_page"

class CollaboratorAutocompleteTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::MembersPage

  setup do
    login_as_test_user
    @unique_prefix = "ac#{SecureRandom.hex(4)}"
    @collab_email = "#{@unique_prefix}@example.com"
    @project_a = create_project("Autocomplete A #{Time.now.to_i}")
    add_collaborator_via_invitation(@project_a, @collab_email)
    login_as_test_user
    @project_b = create_project("Autocomplete B #{Time.now.to_i}")
  end

  test "typing collaborator email shows autocomplete suggestions" do
    navigate_to_members(@project_b)
    type_in_invite_field(@unique_prefix)

    assert_autocomplete_visible
    assert_autocomplete_suggests(@collab_email)
  end

  test "short query does not trigger autocomplete" do
    navigate_to_members(@project_b)
    type_in_invite_field("c")

    assert_autocomplete_hidden
  end

  test "selecting suggestion fills the email field" do
    navigate_to_members(@project_b)
    type_in_invite_field(@unique_prefix)

    assert_autocomplete_suggests(@collab_email)
    find(AUTOCOMPLETE_ITEM, text: @collab_email).click

    field = find(INVITE_INPUT)
    assert_equal @collab_email, field.value, "Selecting a suggestion should fill the email field"
    assert_autocomplete_hidden
  end

  test "escape key closes autocomplete dropdown" do
    navigate_to_members(@project_b)
    type_in_invite_field(@unique_prefix)

    assert_autocomplete_visible
    find(INVITE_INPUT).send_keys(:escape)

    assert_autocomplete_hidden
  end

  test "keyboard navigation selects suggestion with enter" do
    navigate_to_members(@project_b)
    type_in_invite_field(@unique_prefix)

    assert_autocomplete_visible
    find(INVITE_INPUT).send_keys(:down, :enter)

    field = find(INVITE_INPUT)
    assert_equal @collab_email, field.value, "Arrow down + Enter should select the first suggestion"
    assert_autocomplete_hidden
  end

  test "autocomplete does not suggest members of current project" do
    navigate_to_members(@project_a)
    type_in_invite_field(@unique_prefix)

    assert_autocomplete_hidden
  end

  private

  def create_project(name)
    visit_new_project
    fill_project_form(name: name)
    submit_project_form
    assert_on_project_show(name)
    current_path
  end

  def navigate_to_members(project_path)
    visit project_path
    click_link "Members"
    assert_on_members_page
  end

  def add_collaborator_via_invitation(project_path, email)
    navigate_to_members(project_path)
    invite_email(email)
    assert_flash_notice "Invitation sent to #{email}."

    invitation_link = extract_invitation_link_from_letter_opener
    assert invitation_link, "Invitation link should be found in letter_opener email"

    visit invitation_link
    assert_selector "input[value='Accept Invitation']", wait: 10
    click_button "Accept Invitation"
    assert_selector ".flash--notice, [data-testid='flash-notice']", text: /joined/i, wait: 10

    # Sign out the auto-created collaborator before logging back in as test user
    logout
  end

  def extract_invitation_link_from_letter_opener
    letter_opener_dir = Rails.root.join("tmp/letter_opener")
    latest_email_dir = Dir.glob("#{letter_opener_dir}/*/").max_by { |d| File.mtime(d) }
    return nil unless latest_email_dir

    html_file = File.join(latest_email_dir, "rich.html")
    return nil unless File.exist?(html_file)

    content = File.read(html_file)
    match = content.match(%r{(https?://[^"&\s]*?/invitations/[^"&\s<]+)})
    match ? URI.parse(match[1]).request_uri : nil
  end
end
