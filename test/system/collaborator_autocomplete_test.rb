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
    add_collaborator_directly(@project_a, @collab_email)
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

  def add_collaborator_directly(project_path, email)
    project_id = project_path.split("/").last
    collaborator = User.create!(
      email: email,
      password: "password",
      confirmed_at: Time.current
    )
    Project.find(project_id).project_memberships.create!(user: collaborator, role: :member)
  end
end
