# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/project_page"
require_relative "pages/api_keys_page"

require "json"
require "net/http"

class ProjectSnapshotsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::ProjectPage
  include Pages::ApiKeysPage

  setup do
    login_as_test_user
  end

  test "project show sorts pages and filters to a selected snapshot" do
    project_name = "Snapshots Project #{SecureRandom.hex(4)}"
    shared_page = "Shared Page #{SecureRandom.hex(4)}"
    snapshot_only_page = "Snapshot Page #{SecureRandom.hex(4)}"
    ad_hoc_only_page = "Ad-hoc Page #{SecureRandom.hex(4)}"
    older_page = "Older Page #{SecureRandom.hex(4)}"

    create_project(project_name)
    token, project_id = create_api_key_with_project(project_name, "Snapshot E2E #{SecureRandom.hex(4)}")

    # Older ad-hoc capture first so it sits below newer ones in the default sort.
    mcp_create_multi_viewport_screenshot(
      token, project_id,
      page_name: older_page,
      title: "Older first"
    )

    snapshot = mcp_create_snapshot(token, project_id)
    shared_snapshot = mcp_create_multi_viewport_screenshot(
      token, project_id,
      page_name: shared_page,
      title: "Snapshot shared",
      snapshot_id: snapshot["snapshot_id"]
    )
    mcp_create_multi_viewport_screenshot(
      token, project_id,
      page_name: snapshot_only_page,
      title: "Snapshot only",
      snapshot_id: snapshot["snapshot_id"]
    )
    mcp_create_multi_viewport_screenshot(
      token, project_id,
      page_name: ad_hoc_only_page,
      title: "Ad-hoc only"
    )
    shared_ad_hoc = mcp_create_multi_viewport_screenshot(
      token, project_id,
      page_name: shared_page,
      title: "Ad-hoc newer"
    )

    visit "/projects/#{project_id}"
    assert_on_project_show(project_name)
    assert_page_cards_in_order(shared_page, ad_hoc_only_page, snapshot_only_page, older_page)
    assert_snapshot_sidebar_visible
    assert_snapshot_listed snapshot["label"]

    click_snapshot snapshot["label"]

    assert_only_page_cards shared_page, snapshot_only_page
    assert_page_card_not_visible ad_hoc_only_page
    assert_page_card_not_visible older_page
    assert_page_card_screenshot shared_page, shared_snapshot["screenshot_id"]
    assert_not_equal shared_ad_hoc["screenshot_id"].to_i,
      find(PAGE_CARD, text: shared_page)["data-screenshot-id"].to_i

    clear_snapshot_filter

    assert_only_page_cards shared_page, snapshot_only_page, ad_hoc_only_page, older_page
    assert_page_card_screenshot shared_page, shared_ad_hoc["screenshot_id"]
    assert_no_selector SNAPSHOT_SIDEBAR_CLEAR
  end

  private

  def create_project(name)
    visit_projects
    click_link "New project"
    assert_selector FORM, wait: 10
    fill_project_form(name: name)
    submit_project_form
    assert_flash_notice "Project created."
    assert_on_project_show(name)
  end

  def create_api_key_with_project(project_name, key_name)
    token = create_api_key(project_name, key_name)
    project_id = current_url.match(%r{/projects/(\d+)})[1].to_i
    [ token, project_id ]
  end

  def mcp_create_snapshot(token, project_id)
    # Distinct from the fixture commit (abc1234def…) so a debugger isn't
    # confused about which project's snapshot they're looking at when both
    # databases are open side-by-side.
    response = call_mcp_tool(
      token: token,
      tool_name: "create_snapshot",
      arguments: {
        project_id: project_id,
        git_commit: "deadbeef1234567890abcdef1234567890abcdef",
        taken_at: "2026-05-14T12:00:00Z"
      }
    )
    assert_equal "200", response.code, "create_snapshot should return 200"

    result = parse_mcp_result(response)
    assert result["snapshot_id"].present?, "create_snapshot response should include snapshot_id"
    assert_equal "2026-05-14 · deadbee", result["label"],
      "label should be derived from taken_at + short_commit; a wrong shape would surface as a missing sidebar item later"
    result
  end

  def mcp_create_multi_viewport_screenshot(token, project_id, page_name:, title:, snapshot_id: nil)
    arguments = {
      project_id: project_id,
      page_name: page_name,
      title: title,
      viewports: [ { viewport: "desktop", mime_type: "image/png" } ]
    }
    arguments[:snapshot_id] = snapshot_id if snapshot_id

    response = call_mcp_tool(
      token: token,
      tool_name: "create_multi_viewport_screenshot",
      arguments: arguments
    )
    assert_equal "200", response.code, "create_multi_viewport_screenshot should return 200"

    result = parse_mcp_result(response)
    assert result["screenshot_id"].present?, "create_multi_viewport_screenshot response should include screenshot_id"

    # Complete the signed-URL upload for every viewport variant; without this
    # the parent Screenshot stays :pending and never appears in the project
    # show grid's thumbnail set, which would invalidate later assertions.
    upload_to_signed_urls(result["uploads"])
    wait_for_screenshot_ready(result["screenshot_id"])

    result
  end

  def upload_to_signed_urls(uploads)
    image_data = File.binread(TEST_IMAGE_PATH)
    uploads.each do |upload|
      # Route helpers use example.com in the test environment. Keep the signed
      # path/query from the tool response but target Capybara's actual server.
      signed_uri = URI(upload["upload_url"])
      uri = URI("#{app_base_url}#{signed_uri.request_uri}")
      request = Net::HTTP::Put.new(uri)
      request["Content-Type"] = "image/png"
      request.body = image_data
      response = perform_enqueued_jobs do
        Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
      end
      assert_equal "200", response.code,
        "Signed-URL upload should succeed (got #{response.code}: #{response.body})"
    end
  end

  # Waits for ScreenshotDimensionJob to flip status -> :ready. Uses Capybara's
  # synchronize loop (the same retry primitive that powers `assert_selector`)
  # so the wait obeys Capybara.default_max_wait_time and never sleeps blindly.
  def wait_for_screenshot_ready(screenshot_id, max_wait: 15)
    using_wait_time(max_wait) do
      page.document.synchronize(max_wait) do
        unless Screenshot.where(id: screenshot_id, status: :ready).exists?
          actual = Screenshot.where(id: screenshot_id).pick(:status)
          raise Capybara::ElementNotFound,
            "Screenshot ##{screenshot_id} not yet :ready (status: #{actual.inspect})"
        end
      end
    end
  end

  def call_mcp_tool(token:, tool_name:, arguments: {})
    uri = URI("#{app_base_url}/mcp")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}" if token
    request["Content-Type"] = "application/json"
    request.body = {
      jsonrpc: "2.0",
      id: SecureRandom.uuid,
      method: "tools/call",
      params: { name: tool_name, arguments: arguments }
    }.to_json

    Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
  end

  def parse_mcp_result(response)
    body = JSON.parse(response.body)
    JSON.parse(body.dig("result", "content", 0, "text"))
  end
end
