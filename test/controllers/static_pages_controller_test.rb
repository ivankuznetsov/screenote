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
    assert_select "code", text: "brew install ivankuznetsov/tap/screenote"
    assert_select "code", text: "curl -fsSL https://screenote.ai/install.sh | sh"
    assert_select "code", text: "screenote login"
    assert_select "code", text: "screenote login --device"
    assert_no_match(/go install|Go 1\.26|\$\(go env GOPATH\)|screenote --base-url https:\/\/screenote\.ai login/, response.body)
    assert_match(/No Go toolchain or manual <code>PATH<\/code> setup is required/, response.body)
    assert_match(/SSH, tmux, or another headless session/, response.body)
    assert_match(/prints a one-time code and authorization link/, response.body)
    assert_match(/No callback port or SSH forwarding is required/, response.body)
    assert_no_match(/--token|SCREENOTE_TOKEN|Create an API key from a project's/, response.body)
    assert_select "code", text: 'screenote project create --name "My app"'
    assert_select "code", text: "screenote snapshot --manifest snapshot.json"
    assert_select "code", text: "screenote annotation get --annotation <ANNOTATION_ID> --crop-file annotation.png"
    assert_select "code", text: 'screenote annotation resolve --annotation <ANNOTATION_ID> --comment "Verified and resolved"'
    assert_select "a[href='https://github.com/ivankuznetsov/screenote-cli']", minimum: 1
    assert_select "a[href='#{dashboard_path}']", text: "dashboard"
    assert_match(/resolve the annotation idempotently/, response.body)
    assert_no_match(/Resolve or reopen the annotation from the Screenote web review/, response.body)
    assert_match(/lists project feedback rather than filtering results by snapshot/, response.body)
    assert_no_match(/Model Context Protocol|\/plugin install|\/screenote feedback/, response.body)
  end

  test "installer is public shell source with bounded caching" do
    get cli_installer_path

    assert_response :success
    assert_equal "text/x-shellscript", response.media_type
    cache_control = response.headers["Cache-Control"]
    assert_includes cache_control, "public"
    assert_includes cache_control, "max-age=300"
    assert_match(/screenote_\$\{version\}_\$\{os\}_\$\{arch\}\.tar\.gz/, response.body)
    assert_match(/checksum verification failed/, response.body)
    assert_match(/Next: screenote login/, response.body)
  end

  test "self-hosted help keeps an explicit server origin" do
    deployment = Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "https://notes.example"
      },
      production: false
    )

    with_current_deployment(deployment) do
      get help_path

      assert_response :success
      assert_select "code", text: "screenote --base-url https://notes.example login"
      assert_select "code", text: "screenote --base-url https://notes.example login --device"
    end
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
    assert_select "code", text: "curl -fsSL https://screenote.ai/install.sh | sh"
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

  private

  def with_current_deployment(deployment)
    previous = Screenote::Deployment.current
    Screenote::Deployment.instance_variable_set(:@current, deployment)
    yield
  ensure
    Screenote::Deployment.instance_variable_set(:@current, previous)
  end
end
