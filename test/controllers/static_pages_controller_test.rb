# frozen_string_literal: true

require "test_helper"

class StaticPagesControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated user sees landing page" do
    get root_path

    assert_response :success, "Unauthenticated user should get 200 for the landing page"
  end

  test "authenticated user is redirected to projects" do
    sign_in users(:alice)

    get root_path

    assert_redirected_to dashboard_path, "Authenticated user should be redirected to dashboard from landing page"
  end

  test "help page is publicly accessible" do
    get help_path

    assert_response :success, "Unauthenticated user should see the help page"
    assert_select "[data-testid='tool-card']", minimum: 1, message: "Tool cards should render without authentication"
  end

  test "unauthenticated help page shows guest nav" do
    get help_path

    assert_select "a", text: "Sign In", message: "Guest nav should show Sign In link"
    assert_select "a", text: "Get Started", message: "Guest nav should show Get Started link"
  end

  test "authenticated user sees help page with full nav" do
    sign_in users(:alice)

    get help_path

    assert_response :success, "Authenticated user should see the help page"
    assert_select "h1", "Getting Started"
    assert_select "a", text: "Sign In", count: 0, message: "Authenticated user should not see Sign In link"
  end

  test "terms page shows guest nav for unauthenticated user" do
    get terms_path

    assert_response :success, "Unauthenticated user should see the terms page"
    assert_select "a", text: "Sign In", message: "Guest nav should show Sign In link on terms page"
  end

  test "landing page footer links to help" do
    get root_path

    assert_select "a[href='#{help_path}']", text: "Help", message: "Landing footer should link to help page"
  end
end
