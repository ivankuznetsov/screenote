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
  test "show renders the newest version workspace without redirecting" do
    sign_in(@user)
    page = @project.pages.create!(name: "Version order")
    older = page.screenshots.create!(title: "Older version", created_at: 2.days.ago)
    newer = page.screenshots.create!(title: "Newer version", created_at: 1.day.ago)

    get page_path(page)

    assert_response :success
    assert_select "[data-testid='screenshot-workspace']", count: 1
    assert_select "[data-testid='page-detail-title']", page.name
    assert_select "[data-testid='version-sidebar-item'][aria-current='page'][data-version-id='#{newer.id}']", count: 1
    assert_select "[data-testid='version-sidebar-item'][data-version-id='#{older.id}']", count: 1
    assert_select "[data-testid='version-sidebar'] img", count: 0
  end

  test "show uses id as the newest version tie breaker" do
    sign_in(@user)
    page = @project.pages.create!(name: "Tie break")
    timestamp = 1.hour.ago.change(usec: 0)
    lower_id = page.screenshots.create!(title: "Lower id", created_at: timestamp)
    higher_id = page.screenshots.create!(title: "Higher id", created_at: timestamp)

    get page_path(page)

    assert_response :success
    assert_select "[data-testid='version-sidebar-item'][aria-current='page'][data-version-id='#{higher_id.id}']", count: 1
    assert_select "[data-testid='version-sidebar-item'][data-version-id='#{lower_id.id}']", count: 1
  end

  test "show selects a page scoped version and falls back for unavailable values" do
    sign_in(@user)
    page = @project.pages.create!(name: "Scoped versions")
    newest = page.screenshots.create!(title: "Newest", created_at: 1.hour.ago)
    selected = page.screenshots.create!(title: "Selected", created_at: 2.hours.ago)
    cross_page = screenshots(:bob_screenshot)

    get page_path(page, version_id: selected.id)
    assert_response :success
    assert_select "[data-testid='version-sidebar-item'][aria-current='page'][data-version-id='#{selected.id}']", count: 1

    [ "not-an-id", Screenshot.maximum(:id).to_i + 100, cross_page.id ].each do |version_id|
      get page_path(page, version_id: version_id)
      assert_response :success
      assert_select "[data-testid='version-sidebar-item'][aria-current='page'][data-version-id='#{newest.id}']", count: 1
      assert_no_match cross_page.title, response.body
    end
  end

  test "show keeps the empty page management state" do
    sign_in(@user)
    page = @project.pages.create!(name: "Empty page")

    get page_path(page)

    assert_response :success
    assert_select "[data-testid='empty-state']", count: 1
    assert_select "a[href='#{new_page_screenshot_path(page)}']", text: /Upload/
    assert_select "a[href='#{edit_page_path(page)}']", count: 1
    assert_select "form[action='#{page_path(page)}']", count: 1
  end

  test "show renders only the exact page url in the breadcrumb" do
    sign_in(@user)
    page = @project.pages.create!(name: "/energy-digest/uk-energy-digest-2026-07-28/")
    page.screenshots.create!(title: "Production")

    get page_path(page)

    assert_response :success
    assert_select "[data-testid='breadcrumb']", count: 1 do |nodes|
      assert_equal page.name, nodes.first.text.strip
      assert_select "a[href='#{page_path(page)}']", text: page.name, count: 1
    end
    assert_no_match @project.name, css_select("[data-testid='breadcrumb']").first.text
    assert_no_match "Production", css_select("[data-testid='breadcrumb']").first.text
  end

  test "show renders the literal newest pending or failed version" do
    sign_in(@user)
    page = @project.pages.create!(name: "Processing states")
    failed = page.screenshots.create!(title: "Failed older", status: :failed, created_at: 2.hours.ago)
    pending = page.screenshots.create!(title: "Pending newest", status: :pending, created_at: 1.hour.ago)

    get page_path(page)

    assert_response :success
    assert_select(
      "[data-testid='version-sidebar-item'][aria-current='page'][data-version-id='#{pending.id}']",
      text: /Pending newest.*Pending/m,
      count: 1
    )
    assert_select "[data-testid='version-sidebar-item'][data-version-id='#{failed.id}']", text: /Failed older.*Failed/m
  end

  test "version links preserve an available viewport and otherwise use the target default" do
    sign_in(@user)
    page = @project.pages.create!(name: "Responsive versions")
    selected = page.screenshots.create!(title: "Selected")
    selected.screenshot_images.create!(viewport: :desktop)
    selected.screenshot_images.create!(viewport: :mobile)
    with_mobile = page.screenshots.create!(title: "Has mobile")
    with_mobile.screenshot_images.create!(viewport: :desktop)
    with_mobile.screenshot_images.create!(viewport: :mobile)
    desktop_only = page.screenshots.create!(title: "Desktop only")
    desktop_only.screenshot_images.create!(viewport: :desktop)

    get page_path(page, version_id: selected.id, viewport: :mobile)

    assert_response :success
    assert_select(
      "a[data-testid='version-sidebar-item'][data-version-id='#{with_mobile.id}']" \
        "[href='#{page_path(page, version_id: with_mobile.id, viewport: :mobile)}']" \
        "[data-turbo-frame='_top']",
      count: 1
    )
    assert_select(
      "a[data-testid='version-sidebar-item'][data-version-id='#{desktop_only.id}']" \
        "[href='#{page_path(page, version_id: desktop_only.id)}']" \
        "[data-turbo-frame='_top']",
      count: 1
    )
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
