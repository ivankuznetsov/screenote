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
    assert_select "#install-cli", count: 1, message: "Help should lead with CLI installation"
    assert_select "code", text: "go install github.com/ivankuznetsov/screenote-cli/cmd/screenote@latest"
    assert_select "code", text: "screenote --base-url https://screenote.ai login"
    assert_select "code", text: "screenote snapshot --manifest snapshot.json"
    assert_select "a[href='https://github.com/ivankuznetsov/screenote-cli']", minimum: 1
    assert_select "a[href='#{dashboard_path}']", text: "dashboard"
    assert_match(/Resolve or reopen the annotation from the Screenote web review/, response.body)
    assert_match(/lists project feedback rather than filtering results by snapshot/, response.body)
    assert_no_match(/Model Context Protocol|\/plugin install|\/screenote feedback/, response.body)
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

  test "landing page promotes the public CLI install path" do
    get root_path

    assert_response :success
    assert_select "a[href='#{help_path(anchor: "install-cli")}']", text: "Install CLI"
    assert_select "code", text: "go install github.com/ivankuznetsov/screenote-cli/cmd/screenote@latest"
    assert_match(/Screenote CLI/, response.body)
    assert_no_match(/Model Context Protocol|MCP protocol|<code>\/screenote(?:\s|&lt;)/, response.body)
  end

  test "legal pages describe CLI and integration access without MCP-only wording" do
    get terms_path

    assert_response :success
    assert_select "h2", text: /CLI, API, and AI agent access/
    assert_no_match(/Model Context Protocol/, response.body)

    get privacy_path

    assert_response :success
    assert_select "h2", text: /CLI, API, and AI agent access/
    assert_no_match(/Model Context Protocol/, response.body)
  end
end
