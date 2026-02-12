# frozen_string_literal: true

require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
  end

  # Authentication
  test "redirects to sign in when not authenticated" do
    get projects_path
    assert_redirected_to new_session_path
  end

  # Index
  test "index shows user projects" do
    sign_in(@user)
    get projects_path
    assert_response :success
    assert_select ".project-card__name", @project.name
  end

  test "index does not show other users projects" do
    sign_in(@user)
    get projects_path
    assert_response :success
    assert_select ".project-card__name", { text: projects(:bob_project).name, count: 0 }
  end

  test "index shows projects where user is a member" do
    sign_in(users(:bob))
    get projects_path
    assert_response :success
    assert_select ".project-card__name", text: /Alice's Project/
  end

  # Show
  test "show displays project" do
    sign_in(@user)
    get project_path(@project)
    assert_response :success
    assert_select ".project-detail__title", @project.name
  end

  test "show returns not found for other users project" do
    sign_in(@user)
    get project_path(projects(:bob_project))
    assert_response :not_found
  end

  test "member can view project" do
    sign_in(users(:bob))
    get project_path(@project)
    assert_response :success
    assert_select ".project-detail__title", @project.name
  end

  # New
  test "new renders form" do
    sign_in(@user)
    get new_project_path
    assert_response :success
    assert_select "form"
  end

  # Create
  test "create with valid params" do
    sign_in(@user)
    assert_difference "Project.count", 1 do
      post projects_path, params: { project: { name: "New Project", description: "Desc" } }
    end
    assert_redirected_to project_path(Project.last)
    follow_redirect!
    assert_select ".flash--notice", "Project created."
  end

  test "create with invalid params renders form" do
    sign_in(@user)
    assert_no_difference "Project.count" do
      post projects_path, params: { project: { name: "", description: "Desc" } }
    end
    assert_response :unprocessable_entity
  end

  # Edit — owner-only
  test "edit renders form" do
    sign_in(@user)
    get edit_project_path(@project)
    assert_response :success
    assert_select "form"
  end

  test "member cannot edit project" do
    sign_in(users(:bob))
    get edit_project_path(@project)
    assert_redirected_to projects_path
  end

  # Update — owner-only
  test "update with valid params" do
    sign_in(@user)
    patch project_path(@project), params: { project: { name: "Updated" } }
    assert_redirected_to project_path(@project)
    assert_equal "Updated", @project.reload.name
  end

  test "update with invalid params renders form" do
    sign_in(@user)
    patch project_path(@project), params: { project: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "member cannot update project" do
    sign_in(users(:bob))
    patch project_path(@project), params: { project: { name: "Hacked" } }
    assert_redirected_to projects_path
    assert_equal "Alice's Project", @project.reload.name, "Project name should not change"
  end

  # Destroy — owner-only
  test "destroy deletes project" do
    sign_in(@user)
    assert_difference "Project.count", -1 do
      delete project_path(@project)
    end
    assert_redirected_to projects_path
  end

  test "member cannot destroy project" do
    sign_in(users(:bob))
    assert_no_difference "Project.count" do
      delete project_path(@project)
    end
    assert_redirected_to projects_path
  end
end
