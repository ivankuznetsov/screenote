# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated user sees landing page" do
    get root_path

    assert_response :success, "Unauthenticated user should get 200 for the landing page"
  end

  test "authenticated user is redirected to projects" do
    sign_in users(:alice)

    get root_path

    assert_redirected_to dashboard_path, "Authenticated user should be redirected to dashboard from landing page"
  end

  test "help page requires authentication" do
    get help_path

    assert_response :redirect, "Unauthenticated user should be redirected from help page"
  end

  test "authenticated user sees help page" do
    sign_in users(:alice)

    get help_path

    assert_response :success, "Authenticated user should see the help page"
    assert_select "h1", "Getting Started"
  end
end
