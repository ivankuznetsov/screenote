# frozen_string_literal: true

require "test_helper"

class ScreenshotTest < ActiveSupport::TestCase
  MANIFEST_DIGEST = "a" * 64
  ENTRY_DIGEST = "b" * 64

  test "valid screenshot with title and project" do
    screenshot = Screenshot.new(title: "Test", page: pages(:alice_page))
    assert screenshot.valid?, "Screenshot should be valid with title and project"
  end

  test "requires title" do
    screenshot = Screenshot.new(page: pages(:alice_page))
    assert_not screenshot.valid?, "Screenshot should be invalid without title"
    assert screenshot.errors[:title].any?, "Should have title error"
  end

  test "requires page" do
    screenshot = Screenshot.new(title: "Test")
    assert_not screenshot.valid?, "Screenshot should be invalid without page"
  end

  test "width must be positive integer" do
    screenshot = Screenshot.new(title: "Test", page: pages(:alice_page), width: -1)
    assert_not screenshot.valid?, "Screenshot should be invalid with negative width"

    screenshot.width = 0
    assert_not screenshot.valid?, "Screenshot should be invalid with zero width"

    screenshot.width = 1920
    assert screenshot.valid?, "Screenshot should be valid with positive width"
  end

  test "height must be positive integer" do
    screenshot = Screenshot.new(title: "Test", page: pages(:alice_page), height: -1)
    assert_not screenshot.valid?, "Screenshot should be invalid with negative height"

    screenshot.height = 1080
    assert screenshot.valid?, "Screenshot should be valid with positive height"
  end

  test "width and height are optional" do
    screenshot = Screenshot.new(title: "Test", page: pages(:alice_page))
    assert screenshot.valid?, "Screenshot should be valid without dimensions"
  end

  test "belongs to project" do
    screenshot = screenshots(:alice_screenshot)
    assert_equal projects(:alice_project), screenshot.project
  end

  test "snapshot is optional" do
    screenshot = Screenshot.new(title: "Ad-hoc", page: pages(:alice_page), snapshot: nil)

    assert screenshot.valid?, "Screenshot should be valid without a snapshot"
  end

  test "belongs to snapshot when provided" do
    snapshot = snapshots(:latest)
    screenshot = Screenshot.create!(title: "Snapshot capture", page: pages(:alice_page), snapshot: snapshot)

    assert_equal snapshot, screenshot.snapshot
    assert_includes snapshot.screenshots, screenshot
  end

  test "invalid when snapshot belongs to a different project than the page" do
    # Defense-in-depth against direct ActiveRecord writes that bypass the
    # MCP tool's `current_project.snapshots.find_by` scoping.
    cross_project_snapshot = projects(:bob_project).snapshots.create!(
      git_commit: "deadbee", taken_at: Time.current
    )

    screenshot = Screenshot.new(
      title: "Cross-project",
      page: pages(:alice_page),
      snapshot: cross_project_snapshot
    )

    assert_not screenshot.valid?, "Screenshot should be invalid with mismatched snapshot/page project"
    assert screenshot.errors[:snapshot].any?, "Error should attach to :snapshot"
  end

  test "manifest-backed snapshot requires a normalized entry digest" do
    snapshot = projects(:alice_project).snapshots.create!(
      git_commit: "abc1234",
      manifest_digest: MANIFEST_DIGEST
    )
    screenshot = Screenshot.new(title: "Prepared", page: pages(:alice_page), snapshot: snapshot)

    assert_not screenshot.valid?
    assert_includes screenshot.errors[:manifest_entry_digest], "can't be blank"

    screenshot.manifest_entry_digest = "  #{ENTRY_DIGEST.upcase}\n"
    assert screenshot.valid?
    screenshot.save!
    assert_equal ENTRY_DIGEST, screenshot.manifest_entry_digest
  end

  test "manifest entry digest is rejected outside a manifest-backed snapshot" do
    legacy_snapshot = projects(:alice_project).snapshots.create!(git_commit: "abc1234")
    screenshot = Screenshot.new(
      title: "Legacy",
      page: pages(:alice_page),
      snapshot: legacy_snapshot,
      manifest_entry_digest: ENTRY_DIGEST
    )

    assert_not screenshot.valid?
    assert_includes screenshot.errors[:manifest_entry_digest], "requires a manifest-backed snapshot"
  end

  test "manifest entry digest is unique within its snapshot" do
    snapshot = projects(:alice_project).snapshots.create!(
      git_commit: "abc1234",
      manifest_digest: MANIFEST_DIGEST
    )
    snapshot.screenshots.create!(
      title: "First",
      page: pages(:alice_page),
      manifest_entry_digest: ENTRY_DIGEST
    )
    duplicate = snapshot.screenshots.build(
      title: "Second",
      page: pages(:alice_page),
      manifest_entry_digest: ENTRY_DIGEST
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:manifest_entry_digest], "has already been taken"
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "has many annotations" do
    screenshot = screenshots(:alice_screenshot)
    assert screenshot.annotations.count >= 2, "Should have annotations"
  end

  test "default status is pending" do
    screenshot = Screenshot.new
    assert_equal "pending", screenshot.status
  end

  test "status enum values" do
    assert_equal 0, Screenshot.statuses[:pending]
    assert_equal 1, Screenshot.statuses[:ready]
    assert_equal 2, Screenshot.statuses[:failed]
  end

  test "generates upload token before image is attached" do
    screenshot = Screenshot.create!(title: "Token test", page: pages(:alice_page))
    token = screenshot.generate_token_for(:upload)

    assert token.present?, "Should generate a token"
    found = Screenshot.find_by_token_for(:upload, token)
    assert_equal screenshot, found, "Token should resolve to the screenshot"
  end

  test "upload token invalidates after image is attached" do
    screenshot = Screenshot.create!(title: "Token invalidation", page: pages(:alice_page))
    token = screenshot.generate_token_for(:upload)

    screenshot.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "test.png",
      content_type: "image/png"
    )

    found = Screenshot.find_by_token_for(:upload, token)
    assert_nil found, "Token should be invalid after image is attached"
  end

  test "destroying screenshot destroys annotations" do
    screenshot = screenshots(:alice_screenshot)
    annotation_count = screenshot.annotations.count
    assert annotation_count > 0, "Should have annotations to destroy"

    assert_difference "Annotation.count", -annotation_count do
      screenshot.destroy
    end
  end

  test "primary_image returns the desktop variant when present" do
    screenshot = screenshots(:alice_screenshot)
    assert_equal screenshot_images(:alice_screenshot_desktop), screenshot.primary_image
  end

  test "primary_image falls back to first available viewport when desktop is missing" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.destroy_all
    mobile = screenshot.screenshot_images.create!(viewport: :mobile)
    assert_equal mobile, screenshot.primary_image
  end

  test "primary_image picks tablet over mobile via integer enum order in loaded and cold paths" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.destroy_all
    tablet = screenshot.screenshot_images.create!(viewport: :tablet)
    screenshot.screenshot_images.create!(viewport: :mobile)

    # Cold path: re-read from DB, association unloaded.
    cold = Screenshot.find(screenshot.id)
    assert_not cold.screenshot_images.loaded?
    assert_equal tablet, cold.primary_image, "Cold path should prefer tablet (enum 1) over mobile (enum 2)"

    # Loaded path: preload the association so the in-memory branch runs.
    loaded = Screenshot.includes(:screenshot_images).find(screenshot.id)
    assert loaded.screenshot_images.loaded?
    assert_equal tablet, loaded.primary_image, "Loaded path should agree with the cold path"
  end

  test "primary_image returns nil when no screenshot_images exist" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.destroy_all
    assert_nil screenshot.primary_image
  end

  test "image_for returns the matching viewport variant" do
    screenshot = screenshots(:alice_screenshot)
    tablet = screenshot.screenshot_images.create!(viewport: :tablet)
    assert_equal tablet, screenshot.image_for(:tablet)
    assert_equal screenshot_images(:alice_screenshot_desktop), screenshot.image_for(:desktop)
    assert_nil screenshot.image_for(:mobile)
  end

  test "image_for uses a preloaded screenshot image association" do
    screenshot = screenshots(:alice_screenshot)
    tablet = screenshot.screenshot_images.create!(viewport: :tablet)
    loaded = Screenshot.includes(:screenshot_images).find(screenshot.id)

    assert loaded.screenshot_images.loaded?
    assert_equal tablet, loaded.image_for(:tablet)
  end

  test "available_viewports lists viewports that have ScreenshotImage rows" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.create!(viewport: :mobile)
    assert_equal %w[desktop mobile], screenshot.available_viewports
  end

  test "available_viewports keeps enum order on a preloaded association" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.create!(viewport: :mobile)
    screenshot.screenshot_images.create!(viewport: :tablet)
    loaded = Screenshot.includes(:screenshot_images).find(screenshot.id)

    assert loaded.screenshot_images.loaded?
    assert_equal %w[desktop tablet mobile], loaded.available_viewports
  end

  test "recent_first orders tied timestamps by descending id" do
    page = pages(:alice_page)
    timestamp = 1.hour.ago.change(usec: 0)
    lower_id = page.screenshots.create!(title: "Lower id", created_at: timestamp)
    higher_id = page.screenshots.create!(title: "Higher id", created_at: timestamp)

    ordered_ids = page.screenshots.where(id: [ lower_id.id, higher_id.id ]).recent_first.ids

    assert_equal [ higher_id.id, lower_id.id ], ordered_ids
  end

  test "default_viewport is desktop when desktop variant exists" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.create!(viewport: :tablet)
    assert_equal "desktop", screenshot.default_viewport
  end

  test "default_viewport falls back to first available when desktop is missing" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.destroy_all
    screenshot.screenshot_images.create!(viewport: :mobile)
    screenshot.screenshot_images.create!(viewport: :tablet)
    assert_equal "tablet", screenshot.default_viewport
  end

  test "default_viewport is nil when no variants exist" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.destroy_all
    assert_nil screenshot.default_viewport
  end
end
