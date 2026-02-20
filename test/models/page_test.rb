# frozen_string_literal: true

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

  test "ordered scope sorts by created_at" do
    project = projects(:alice_project)
    pages = project.pages.ordered
    assert_equal pages.sort_by(&:created_at), pages.to_a
  end
end
