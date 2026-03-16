# frozen_string_literal: true

require "test_helper"

class CollaboratorSuggestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:alice)
    @member = users(:bob)
    @project = projects(:alice_project)
    @second_project = projects(:alice_second_project)
  end

  # Authorization

  test "requires authentication" do
    get project_collaborator_suggestions_path(@project), params: { q: "bob" }
    assert_redirected_to new_session_path
  end

  test "requires owner role" do
    sign_in(@member)
    get project_collaborator_suggestions_path(@project), params: { q: "test" }
    assert_redirected_to projects_path
  end

  # Suggestions

  test "returns collaborators from other projects" do
    sign_in(@owner)
    get project_collaborator_suggestions_path(@second_project), params: { q: "bob" }
    assert_response :success
    assert_includes response.body, users(:bob).email
  end

  test "excludes current project members" do
    sign_in(@owner)
    get project_collaborator_suggestions_path(@project), params: { q: "bob" }
    assert_response :success
    refute_includes response.body, users(:bob).email
  end

  test "returns no content for short queries" do
    sign_in(@owner)
    get project_collaborator_suggestions_path(@project), params: { q: "b" }
    assert_response :no_content
  end

  test "returns empty for no matches" do
    sign_in(@owner)
    get project_collaborator_suggestions_path(@second_project), params: { q: "zzzzz" }
    assert_response :success
    assert_empty response.body.strip
  end

  test "caps results at 8" do
    sign_in(@owner)
    get project_collaborator_suggestions_path(@second_project), params: { q: "example" }
    assert_response :success
    assert response.body.scan("autocomplete-suggestions__item").size <= 8
  end
end
