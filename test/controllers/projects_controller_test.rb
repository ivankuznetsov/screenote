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

  test "show orders pages by newest screenshot and falls back to page created_at" do
    sign_in(@user)
    project = @user.owned_projects.create!(name: "Ordering project")
    older = project.pages.create!(name: "Older", created_at: 6.days.ago)
    no_screenshots = project.pages.create!(name: "No screenshots", created_at: 1.hour.ago)
    newest = project.pages.create!(name: "Newest", created_at: 7.days.ago)

    older.screenshots.create!(title: "Older shot", status: :ready, created_at: 4.days.ago)
    newest.screenshots.create!(title: "Newest shot", status: :ready, created_at: 10.minutes.ago)

    get project_path(project)

    assert_response :success
    assert_equal [ newest.id, no_screenshots.id, older.id ], page_card_page_ids
  end

  test "show without snapshot filter returns all pages" do
    sign_in(@user)
    project = @user.owned_projects.create!(name: "All pages project")
    first_page = project.pages.create!(name: "First")
    second_page = project.pages.create!(name: "Second")
    first_page.screenshots.create!(title: "First shot", status: :ready)

    get project_path(project)

    assert_response :success
    assert_equal [ first_page.id, second_page.id ].sort, page_card_page_ids.sort
    # Guards the `screenshots_count_cache` SELECT alias the view reads at
    # `app/views/projects/show.html.erb:39-40`: drop the alias and these
    # counts render blank with all other tests green.
    assert_includes page_card_version_counters, "1 version"
    assert_includes page_card_version_counters, "0 versions"
  end

  test "show filters to pages captured in the selected snapshot" do
    sign_in(@user)
    project = @user.owned_projects.create!(name: "Snapshot project")
    snapshot = project.snapshots.create!(git_commit: "abc1234", taken_at: Time.current)
    captured = project.pages.create!(name: "Captured")
    also_captured = project.pages.create!(name: "Also captured")
    ad_hoc_only = project.pages.create!(name: "Ad-hoc only")

    captured.screenshots.create!(title: "Captured shot", snapshot: snapshot, status: :ready)
    also_captured.screenshots.create!(title: "Also captured shot", snapshot: snapshot, status: :ready)
    ad_hoc_only.screenshots.create!(title: "Ad-hoc shot", status: :ready)

    get project_path(project, snapshot_id: snapshot.id)

    assert_response :success
    assert_equal [ captured.id, also_captured.id ].sort, page_card_page_ids.sort
    # Guards screenshots_count_cache on the filtered path too — a refactor
    # that scopes the alias to only the unfiltered SELECT would render blank
    # counters with every other assertion green.
    assert page_card_version_counters.all? { |c| c =~ /\d+ version/ },
      "All page cards should render their version counter; got #{page_card_version_counters.inspect}"
  end

  test "show filtered thumbnails bound query count" do
    sign_in(@user)
    project = @user.owned_projects.create!(name: "Bounded query project")
    snapshot = project.snapshots.create!(git_commit: "abc1234", taken_at: Time.current)

    3.times do |i|
      page = project.pages.create!(name: "Page #{i}")
      screenshot = page.screenshots.create!(title: "Shot #{i}", snapshot: snapshot, status: :ready)
      %i[desktop tablet mobile].each { |vp| screenshot.screenshot_images.create!(viewport: vp) }
    end

    get project_path(project, snapshot_id: snapshot.id) # warm caches

    # Wrap the second call so a refactor that drops the page_thumbnails
    # subselect and resolves thumbnails per-card can't silently regress R2.
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless /SCHEMA|TRANSACTION/i.match?(payload[:name].to_s) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get project_path(project, snapshot_id: snapshot.id)
    end

    assert_response :success
    # Tight upper bound near observed baseline so a partial N+1 regression
    # (e.g. per-card membership/project lookup) trips this even when the
    # subselect itself stays in place.
    assert queries.size <= 12,
      "Filtered show should not issue per-page thumbnail queries (saw #{queries.size}): #{queries.last(40).inspect}"
  end

  test "show renders snapshot screenshot as thumbnail when filtered" do
    sign_in(@user)
    project = @user.owned_projects.create!(name: "Snapshot thumbnails project")
    snapshot = project.snapshots.create!(git_commit: "abc1234", taken_at: Time.current)
    page = project.pages.create!(name: "Shared page")

    snapshot_screenshot = page.screenshots.create!(
      title: "Snapshot shot",
      snapshot: snapshot,
      status: :ready,
      created_at: 2.hours.ago
    )
    ad_hoc_screenshot = page.screenshots.create!(
      title: "Newer ad-hoc shot",
      status: :ready,
      created_at: 5.minutes.ago
    )

    get project_path(project, snapshot_id: snapshot.id)

    assert_response :success
    assert_equal snapshot_screenshot.id, page_card_screenshot_ids.fetch(page.id)
    assert_not_equal ad_hoc_screenshot.id, page_card_screenshot_ids.fetch(page.id)
  end

  test "show ignores unknown snapshot filter" do
    sign_in(@user)
    project = @user.owned_projects.create!(name: "Unknown snapshot project")
    project.snapshots.create!(git_commit: "abc1234", taken_at: Time.current)
    page = project.pages.create!(name: "Visible")

    get project_path(project, snapshot_id: Snapshot.maximum(:id).to_i + 100)

    assert_response :success
    assert_equal [ page.id ], page_card_page_ids
    assert_select "[data-testid='snapshot-sidebar']",
      { count: 1 }, "Sidebar should still render so user can choose a valid snapshot"
    assert_select "[data-testid='snapshot-sidebar-clear']",
      { count: 0 }, "Clear link should not appear when no active snapshot is bound"
  end

  test "show ignores snapshot filter from another project" do
    sign_in(@user)
    project = @user.owned_projects.create!(name: "Cross snapshot project")
    page = project.pages.create!(name: "Visible")
    other_snapshot = projects(:bob_project).snapshots.create!(git_commit: "abc1234", taken_at: Time.current)

    get project_path(project, snapshot_id: other_snapshot.id)

    assert_response :success
    assert_equal [ page.id ], page_card_page_ids
  end

  test "show lists recent snapshots in the sidebar" do
    sign_in(@user)
    snapshot = @project.snapshots.create!(
      git_commit: "abc1234def567890",
      taken_at: Time.zone.parse("2026-05-14 12:00:00")
    )

    get project_path(@project, snapshot_id: snapshot.id)

    assert_response :success
    assert_select "[data-testid='snapshot-sidebar']"
    assert_select "[data-testid='snapshot-sidebar-item']", text: "2026-05-14 · abc1234"
    assert_select "[data-testid='snapshot-sidebar-clear']", text: "All screens"
  end

  test "show caps the sidebar at 10 snapshots when there are more" do
    sign_in(@user)
    project = @user.owned_projects.create!(name: "Many snapshots project")
    12.times do |i|
      project.snapshots.create!(
        git_commit: "a%07x" % i,
        taken_at: Time.zone.parse("2026-05-01 12:00:00") + i.days
      )
    end

    get project_path(project)

    assert_response :success
    assert_select "[data-testid='snapshot-sidebar-item']", count: 10
  end

  test "show prepends the active snapshot when it is older than the recent ten" do
    sign_in(@user)
    project = @user.owned_projects.create!(name: "Stale active snapshot project")
    older = project.snapshots.create!(
      git_commit: "01dabcd",
      taken_at: Time.zone.parse("2026-01-01 12:00:00")
    )
    10.times do |i|
      project.snapshots.create!(
        git_commit: "f%06x" % i,
        taken_at: Time.zone.parse("2026-05-01 12:00:00") + i.days
      )
    end

    get project_path(project, snapshot_id: older.id)

    assert_response :success
    # Older snapshot must still appear in the sidebar even though it falls
    # outside the recent-10 window.
    assert_select "[data-testid='snapshot-sidebar-item'][data-snapshot-id='#{older.id}']",
      { count: 1 }, "Active snapshot should be prepended into the sidebar even when older than recent-10"
    # And the sidebar still caps at 10 rows so the active row replaces the
    # oldest in-window row rather than expanding to 11.
    assert_select "[data-testid='snapshot-sidebar-item']", count: 10
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

  # Plan limit enforcement

  test "free user at project limit is redirected from new" do
    sign_in(users(:bob))
    assert_equal 1, users(:bob).owned_projects.count, "Precondition: Bob owns 1 project"
    get new_project_path
    assert_redirected_to subscription_path
    follow_redirect!
    assert_select ".flash--alert"
  end

  test "free user at project limit is redirected from create" do
    sign_in(users(:bob))
    assert_no_difference "Project.count" do
      post projects_path, params: { project: { name: "Blocked Project", description: "Nope" } }
    end
    assert_redirected_to subscription_path
  end

  test "pro user can create projects beyond free limit" do
    sign_in(users(:alice))
    assert_difference "Project.count", 1 do
      post projects_path, params: { project: { name: "Another Pro Project", description: "Yes" } }
    end
    assert_redirected_to project_path(Project.last)
  end

  private

  def page_card_page_ids
    css_select("[data-testid='page-card']").map { |node| node["data-page-id"].to_i }
  end

  def page_card_screenshot_ids
    css_select("[data-testid='page-card']").to_h do |node|
      [ node["data-page-id"].to_i, node["data-screenshot-id"].to_i ]
    end
  end

  def page_card_version_counters
    css_select("[data-testid='page-card'] .page-card__meta").map { |node| node.text.strip }
  end
end
