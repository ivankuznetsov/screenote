# frozen_string_literal: true

require "test_helper"

class ApiKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @api_key = api_keys(:alice_key)
  end

  # Authentication
  test "redirects to sign in when not authenticated" do
    get project_api_keys_path(@project)
    assert_redirected_to new_session_path
  end

  # Authorization — member blocked
  test "member cannot access API keys index" do
    sign_in(users(:bob))
    get project_api_keys_path(@project)
    assert_redirected_to projects_path
  end

  test "member cannot create API keys" do
    sign_in(users(:bob))
    assert_no_difference "ApiKey.count" do
      post project_api_keys_path(@project), params: { api_key: { name: "Hack Key" } }
    end
    assert_redirected_to projects_path
  end

  test "member cannot destroy API keys" do
    sign_in(users(:bob))
    delete project_api_key_path(@project, @api_key)
    assert_redirected_to projects_path
    assert_not @api_key.reload.revoked?, "Key should not be revoked by member"
  end

  # Index
  test "index shows active API keys" do
    sign_in(@user)
    get project_api_keys_path(@project)
    assert_response :success
    assert_select ".api-key-item__name", @api_key.name
  end

  test "index does not show other users keys" do
    sign_in(@user)
    get project_api_keys_path(@project)
    assert_response :success
    assert_select ".api-key-item__name", { text: api_keys(:bob_key).name, count: 0 }
  end

  test "empty index explains API keys as CLI automation credentials" do
    sign_in(@user)
    project = projects(:alice_second_project)

    get project_api_keys_path(project)

    assert_response :success
    assert_select ".empty-state__description", text: /Screenote CLI and agent automation/
    assert_no_match(/via MCP/, response.body)
  end

  test "cannot access other users project keys" do
    sign_in(@user)
    get project_api_keys_path(projects(:bob_project))
    assert_response :not_found
  end

  # New
  test "new renders form" do
    sign_in(@user)
    get new_project_api_key_path(@project)
    assert_response :success
    assert_select "form"
    assert_select "input[placeholder='e.g. CI snapshot uploader']"
  end

  # Create
  test "create generates a new API key" do
    sign_in(@user)

    assert_difference "ApiKey.count", 1 do
      post project_api_keys_path(@project), params: { api_key: { name: "Deploy Key" } }
    end

    assert_redirected_to project_api_keys_path(@project)
    key = ApiKey.last
    assert_equal "Deploy Key", key.name
    assert key.token_digest.present?, "Token digest should be generated"
    assert key.token_prefix.start_with?("sk_proj_"), "Token prefix should have correct prefix"
  end

  test "create shows token in flash for one-time copy" do
    sign_in(@user)
    post project_api_keys_path(@project), params: { api_key: { name: "Flash Key" } }

    assert flash[:api_key_token].present?, "Token should be in flash"
    assert flash[:api_key_token].start_with?("sk_proj_")
  end

  test "create with blank name renders form" do
    sign_in(@user)

    assert_no_difference "ApiKey.count" do
      post project_api_keys_path(@project), params: { api_key: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  # Destroy (revoke)
  test "destroy revokes the key" do
    sign_in(@user)

    assert_no_difference "ApiKey.count" do
      delete project_api_key_path(@project, @api_key)
    end

    assert_redirected_to project_api_keys_path(@project)
    assert @api_key.reload.revoked?, "Key should be revoked"
  end

  test "cannot revoke already-revoked key" do
    sign_in(@user)
    delete project_api_key_path(@project, api_keys(:alice_key_revoked))
    assert_response :not_found
  end
end
