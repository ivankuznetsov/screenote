# frozen_string_literal: true

require "test_helper"

class ScreenshotImageTest < ActiveSupport::TestCase
  test "valid with screenshot and viewport" do
    si = ScreenshotImage.new(screenshot: screenshots(:alice_screenshot), viewport: :mobile)
    assert si.valid?, "Should be valid with screenshot + viewport"
  end

  test "requires screenshot" do
    si = ScreenshotImage.new(viewport: :desktop)
    assert_not si.valid?, "Should be invalid without screenshot"
  end

  test "viewport is unique per screenshot" do
    existing = screenshot_images(:alice_screenshot_desktop)
    duplicate = ScreenshotImage.new(screenshot: existing.screenshot, viewport: :desktop)
    assert_not duplicate.valid?, "Should not allow two desktop variants on the same screenshot"
    assert_includes duplicate.errors[:viewport], "has already been taken"
  end

  test "database-level unique index on (screenshot_id, viewport)" do
    existing = screenshot_images(:alice_screenshot_desktop)
    duplicate = ScreenshotImage.new(screenshot: existing.screenshot, viewport: :desktop)
    assert_raises(ActiveRecord::RecordNotUnique) do
      duplicate.save(validate: false)
    end
  end

  test "viewport enum values" do
    assert_equal 0, ScreenshotImage.viewports[:desktop]
    assert_equal 1, ScreenshotImage.viewports[:tablet]
    assert_equal 2, ScreenshotImage.viewports[:mobile]
  end

  test "viewport predicates use prefix" do
    si = screenshot_images(:alice_screenshot_desktop)
    assert si.viewport_desktop?
    assert_not si.viewport_mobile?
  end

  test "status enum values and defaults to pending" do
    assert_equal 0, ScreenshotImage.statuses[:pending]
    assert_equal 1, ScreenshotImage.statuses[:ready]
    assert_equal 2, ScreenshotImage.statuses[:failed]
    assert ScreenshotImage.new.status_pending?
  end

  test "width must be positive integer when present" do
    si = ScreenshotImage.new(screenshot: screenshots(:alice_screenshot), viewport: :tablet, width: -1)
    assert_not si.valid?
  end

  test "generates upload token before image is attached" do
    si = ScreenshotImage.create!(screenshot: screenshots(:alice_screenshot), viewport: :mobile)
    token = si.generate_token_for(:upload)
    assert token.present?
    assert_equal si, ScreenshotImage.find_by_token_for(:upload, token)
  end

  test "upload token invalidates after image is attached" do
    si = ScreenshotImage.create!(screenshot: screenshots(:alice_screenshot), viewport: :mobile)
    token = si.generate_token_for(:upload)

    si.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "test.png",
      content_type: "image/png"
    )

    assert_nil ScreenshotImage.find_by_token_for(:upload, token),
      "Token should invalidate after attachment"
  end

  test "destroying screenshot destroys its screenshot_images" do
    screenshot = screenshots(:alice_screenshot)
    count = screenshot.screenshot_images.count
    assert count > 0

    assert_difference "ScreenshotImage.count", -count do
      screenshot.destroy
    end
  end

  test "rejects non-png non-jpeg content types" do
    si = ScreenshotImage.new(screenshot: screenshots(:alice_screenshot), viewport: :tablet)
    si.image.attach(io: StringIO.new("junk"), filename: "test.gif", content_type: "image/gif")
    assert_not si.valid?
    assert_includes si.errors[:image].join, "PNG or JPEG"
  end

  test "status change syncs parent Screenshot to :ready when all siblings ready" do
    screenshot = screenshots(:alice_screenshot)
    si = screenshot_images(:alice_screenshot_desktop)
    si.update!(status: :pending)
    screenshot.update_columns(status: Screenshot.statuses[:pending])

    si.update!(status: :ready)

    assert_equal "ready", screenshot.reload.status
  end

  test "status change syncs parent Screenshot to :failed when any sibling failed" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.create!(viewport: :mobile, status: :pending)
    screenshot.update_columns(status: Screenshot.statuses[:pending])

    screenshot.screenshot_images.find_by(viewport: :mobile).update!(status: :failed)

    assert_equal "failed", screenshot.reload.status
  end

  test "creating a pending sibling drops parent from :ready back to :pending" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.screenshot_images.find_by(viewport: :desktop).update!(status: :pending)
    screenshot.screenshot_images.find_by(viewport: :desktop).update!(status: :ready)
    assert_equal "ready", screenshot.reload.status

    screenshot.screenshot_images.create!(viewport: :mobile, status: :pending)

    assert_equal "pending", screenshot.reload.status,
      "New pending sibling fires after_save status callback and drops parent back to :pending"
  end
end
