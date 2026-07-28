# frozen_string_literal: true

require "test_helper"

class ScreenshotImageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  MANIFEST_DIGEST = "a" * 64
  ENTRY_DIGEST = "b" * 64
  CONTENT_DIGEST = "c" * 64

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

  test "declares the named overview variants at their exact output dimensions" do
    variants = ScreenshotImage.attachment_reflections.fetch("image").named_variants

    assert_equal(
      { resize_to_fill: [ 480, 270 ] },
      variants.fetch(:page_card_1x).transformations
    )
    assert_equal(
      { resize_to_fill: [ 960, 540 ] },
      variants.fetch(:page_card_2x).transformations
    )
    assert_equal(
      { resize_to_fill: [ 240, 160 ] },
      variants.fetch(:project_strip).transformations
    )
  end

  test "overview variants require preloaded tracked records" do
    image = screenshot_images(:alice_screenshot_desktop)
    image.image.attach(
      io: StringIO.new(file_fixture("test_image.png").binread),
      filename: "test_image.png",
      content_type: "image/png"
    )
    image.thumbnail_variants.each do |variant|
      image.image.blob.variant_records.create!(variation_digest: variant.variation.digest)
    end

    assert_not ScreenshotImage.find(image.id).overview_variants_warmed?,
      "Overview rendering must not query an association that was not preloaded"

    preloaded = ScreenshotImage.includes(ScreenshotImage::OVERVIEW_IMAGE_PRELOAD).find(image.id)
    assert preloaded.image.blob.association(:variant_records).loaded?
    assert preloaded.overview_variants_warmed?
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

  test "content SHA is optional for legacy images" do
    image = ScreenshotImage.new(screenshot: screenshots(:alice_screenshot), viewport: :mobile)

    assert image.valid?
    assert_nil image.content_sha256
  end

  test "manifest-backed image requires a normalized content SHA" do
    snapshot = projects(:alice_project).snapshots.create!(
      git_commit: "abc1234",
      manifest_digest: MANIFEST_DIGEST
    )
    screenshot = snapshot.screenshots.create!(
      page: pages(:alice_page),
      title: "Prepared",
      manifest_entry_digest: ENTRY_DIGEST
    )
    image = screenshot.screenshot_images.build(viewport: :mobile)

    assert_not image.valid?
    assert_includes image.errors[:content_sha256], "can't be blank"
    assert_includes image.errors[:expected_content_type], "can't be blank"

    image.content_sha256 = "  #{CONTENT_DIGEST.upcase}\n"
    image.expected_content_type = " IMAGE/PNG\n"
    assert image.valid?
    image.save!
    assert_equal CONTENT_DIGEST, image.content_sha256
    assert_equal "image/png", image.expected_content_type
  end

  test "content SHA must be a SHA-256 hex digest" do
    image = ScreenshotImage.new(
      screenshot: screenshots(:alice_screenshot),
      viewport: :mobile,
      content_sha256: "not-a-digest"
    )

    assert_not image.valid?
    assert_includes image.errors[:content_sha256], "must be a 64-character hexadecimal SHA-256"
  end

  test "after_create_commit does not enqueue dimension job when no image attached" do
    # Blank ScreenshotImage (signed-upload flow — blob arrives later). Without
    # the guard, the job would fire, log a warning, and exit — pure noise.
    screenshot = screenshots(:alice_screenshot)

    assert_no_enqueued_jobs only: ScreenshotDimensionJob do
      screenshot.screenshot_images.create!(viewport: :mobile)
    end
  end

  test "after_create_commit does not enqueue dimension job when variant already ready" do
    # Backfill rows copy status=:ready from the parent. No need to re-analyze.
    screenshot = screenshots(:alice_screenshot)

    assert_no_enqueued_jobs only: ScreenshotDimensionJob do
      si = screenshot.screenshot_images.build(viewport: :mobile, status: :ready, width: 375, height: 812)
      si.image.attach(
        io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
        filename: "m.png", content_type: "image/png"
      )
      si.save!
    end
  end

  test "ensure_dimension_processing enqueues the current attachment generation" do
    screenshot = screenshots(:alice_screenshot)
    si = screenshot.screenshot_images.create!(viewport: :mobile)
    si.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "generation.png",
      content_type: "image/png"
    )

    assert_enqueued_with(job: ScreenshotDimensionJob, args: [ si, si.image.blob.id ]) do
      si.ensure_dimension_processing
    end
  end

  test "rollback_to_screenshots! restores Screenshot width/height/status from the variant" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.image.purge if screenshot.image.attached?
    screenshot.update_columns(width: nil, height: nil, status: Screenshot.statuses[:pending])
    si = screenshot.screenshot_images.find_or_create_by(viewport: :desktop)
    si.update!(width: 1920, height: 1080, status: :ready)
    si.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "d.png", content_type: "image/png"
    )

    ScreenshotImage.rollback_to_screenshots!(apply: true, logger: StringIO.new)

    screenshot.reload
    assert screenshot.image.attached?
    assert_equal 1920, screenshot.width
    assert_equal 1080, screenshot.height
    assert_equal "ready", screenshot.status,
      "Rollback must preserve status — otherwise Page.latest_screenshot (filters by :ready) loses this row"
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
