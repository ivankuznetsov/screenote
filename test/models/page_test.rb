# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class PageTest < ActiveSupport::TestCase
  test "valid page with name and project" do
    page = Page.new(name: "Login", project: projects(:alice_project))
    assert page.valid?, "Page should be valid with name and project"
  end

  test "requires name" do
    page = Page.new(project: projects(:alice_project))
    assert_not page.valid?, "Page should be invalid without name"
    assert page.errors[:name].any?, "Should have name error"
  end

  test "requires project" do
    page = Page.new(name: "Login")
    assert_not page.valid?, "Page should be invalid without project"
  end

  test "name must be 255 characters or fewer" do
    page = Page.new(name: "x" * 256, project: projects(:alice_project))
    assert_not page.valid?, "Page should be invalid with name over 255 chars"

    page.name = "x" * 255
    assert page.valid?, "Page should be valid with name at 255 chars"
  end

  test "name must be unique within project (case insensitive)" do
    existing = pages(:alice_page)
    duplicate = Page.new(name: existing.name.upcase, project: existing.project)
    assert_not duplicate.valid?, "Page should be invalid with duplicate name in same project"
  end

  test "same name allowed in different projects" do
    page = Page.new(name: pages(:alice_page).name, project: projects(:bob_project))
    assert page.valid?, "Page should be valid with same name in different project"
  end

  test "belongs to project" do
    page = pages(:alice_page)
    assert_equal projects(:alice_project), page.project
  end

  test "has many screenshots" do
    page = pages(:alice_page)
    assert_includes page.screenshots, screenshots(:alice_screenshot)
  end

  test "destroying page destroys screenshots" do
    page = pages(:alice_page)
    screenshot_count = page.screenshots.count
    assert screenshot_count > 0, "Should have screenshots to destroy"

    assert_difference "Screenshot.count", -screenshot_count do
      page.destroy
    end
  end

  test "latest screenshot is the newest ready version by created_at then id" do
    page = pages(:alice_page)
    newest = page.screenshots.create!(title: "Newest", status: :ready, created_at: 1.minute.from_now)
    page.screenshots.create!(title: "Higher id, older", status: :ready, created_at: 1.day.ago)
    page.screenshots.create!(title: "Newer but pending", status: :pending, created_at: 1.hour.from_now)

    assert_equal newest, page.latest_screenshot

    tied = page.screenshots.create!(title: "Same time, higher id", status: :ready, created_at: newest.created_at)
    assert_equal tied, page.reload.latest_screenshot
  end

  test "latest screenshot preloads one version per page" do
    alice_newest = pages(:alice_page).screenshots.create!(title: "Alice newest", status: :ready, created_at: 1.minute.from_now)
    bob_newest = pages(:bob_page).screenshots.create!(title: "Bob newest", status: :ready, created_at: 1.minute.from_now)

    loaded = Page.where(id: [ pages(:alice_page), pages(:bob_page), pages(:alice_page_pending) ])
      .includes(:latest_screenshot).index_by(&:id)

    assert_equal alice_newest, loaded[pages(:alice_page).id].latest_screenshot
    assert_equal bob_newest, loaded[pages(:bob_page).id].latest_screenshot
    assert_nil loaded[pages(:alice_page_pending).id].latest_screenshot
  end

  test "find_or_create_by_name! finds existing page case-insensitively" do
    existing = pages(:alice_page)
    found = Page.find_or_create_by_name!(existing.project, existing.name.upcase)
    assert_equal existing, found, "Should find existing page regardless of case"
  end

  test "find_or_create_by_name! creates page when not found" do
    project = projects(:alice_project)
    assert_difference "Page.count", 1 do
      page = Page.find_or_create_by_name!(project, "Brand New Page")
      assert_equal "Brand New Page", page.name
      assert_equal project, page.project
    end
  end

  test "display path removes captured query and fragment state" do
    page = Page.new(name: "/admin/users?page=1&q=test#selected")

    assert_equal "/admin/users", page.display_path
    assert_equal [ "admin", "users" ], page.path_segments
  end

  test "display path extracts the path from an absolute captured url" do
    page = Page.new(name: "https://rabata.io/admin/users?page=1")

    assert_equal "/admin/users", page.display_path
  end

  test "display path preserves human-readable page names including URI punctuation" do
    [ "Homepage Design", "What? now", "FAQ #2", "Design:V2" ].each do |name|
      assert_equal name, Page.new(name: name).display_path
    end
  end

  test "display path removes transient state from a malformed captured path" do
    page = Page.new(name: "/admin/users bad?page=1#selected")

    assert_equal "/admin/users bad", page.display_path
  end

  test "path prefix matching includes the route and its descendants" do
    assert Page.new(name: "/admin?tab=overview").within_path_prefix?("/admin")
    assert Page.new(name: "/admin/users?page=1").within_path_prefix?("/admin")
    assert_not Page.new(name: "/administrator").within_path_prefix?("/admin")
  end
end
