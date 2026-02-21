# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @page = pages(:alice_page)
  end

  # Authentication
  test "redirects to sign in when not authenticated" do
    get page_path(@page)
    assert_redirected_to new_session_path
  end

  # Show
  test "show displays page with versions" do
    sign_in(@user)
    get page_path(@page)
    assert_response :success
    assert_select "[data-testid='page-detail-title']", @page.name
  end

  test "show returns not found for other users page" do
    sign_in(@user)
    get page_path(pages(:bob_page))
    assert_response :not_found
  end

  # New
  test "new renders form" do
    sign_in(@user)
    get new_project_page_path(@project)
    assert_response :success
    assert_select "form"
  end

  # Create
  test "create with valid params" do
    sign_in(@user)

    assert_difference "Page.count", 1 do
      post project_pages_path(@project), params: { page: { name: "Settings" } }
    end

    page = Page.last
    assert_redirected_to page_path(page)
    assert_equal "Settings", page.name
    assert_equal @project.id, page.project_id
  end

  test "create with invalid params renders form" do
    sign_in(@user)

    assert_no_difference "Page.count" do
      post project_pages_path(@project), params: { page: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "create with duplicate name renders form" do
    sign_in(@user)

    assert_no_difference "Page.count" do
      post project_pages_path(@project), params: { page: { name: @page.name } }
    end
    assert_response :unprocessable_entity
  end

  # Edit
  test "edit renders form" do
    sign_in(@user)
    get edit_page_path(@page)
    assert_response :success
    assert_select "form"
  end

  # Update
  test "update with valid params" do
    sign_in(@user)
    patch page_path(@page), params: { page: { name: "Renamed" } }
    assert_redirected_to page_path(@page)
    assert_equal "Renamed", @page.reload.name
  end

  test "update with invalid params renders form" do
    sign_in(@user)
    patch page_path(@page), params: { page: { name: "" } }
    assert_response :unprocessable_entity
  end

  # Destroy
  test "destroy deletes page" do
    sign_in(@user)

    assert_difference "Page.count", -1 do
      delete page_path(@page)
    end
    assert_redirected_to project_path(@project)
  end

  test "destroy returns not found for other users page" do
    sign_in(@user)

    assert_no_difference "Page.count" do
      delete page_path(pages(:bob_page))
    end
    assert_response :not_found
  end
end
