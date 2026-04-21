# frozen_string_literal: true

require "test_helper"

class AnnotationCropServiceTest < ActiveSupport::TestCase
  setup do
    @screenshot_image = screenshot_images(:alice_screenshot_desktop)
    @screenshot_image.update!(width: 400, height: 300)
    @screenshot_image.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "test.png", content_type: "image/png"
    )
  end

  test "crops point annotation" do
    annotation = annotations(:point_annotation)
    result = AnnotationCropService.crop(@screenshot_image, annotation)
    assert result.present?
    assert_nothing_raised { Base64.strict_decode64(result) }
  end

  test "crops region annotation" do
    annotation = annotations(:region_annotation)
    result = AnnotationCropService.crop(@screenshot_image, annotation)
    assert result.present?
    assert_nothing_raised { Base64.strict_decode64(result) }
  end

  test "caches crop result" do
    annotation = annotations(:point_annotation)
    result1 = AnnotationCropService.crop(@screenshot_image, annotation)
    result2 = AnnotationCropService.crop(@screenshot_image, annotation)
    assert_equal result1, result2
  end

  test "class method delegates to instance" do
    annotation = annotations(:point_annotation)
    service = AnnotationCropService.new(@screenshot_image, annotation)
    assert_equal service.crop, AnnotationCropService.crop(@screenshot_image, annotation)
  end

  test "annotation.crop delegates to the service through the matching ScreenshotImage" do
    annotation = annotations(:point_annotation)
    # Ensure the annotation's viewport matches our test ScreenshotImage
    annotation.update!(viewport: :desktop)
    @screenshot_image.update!(status: :ready)
    assert_equal AnnotationCropService.crop(@screenshot_image, annotation), annotation.crop
  end

  test "annotation.crop returns nil when the ScreenshotImage is not ready" do
    annotation = annotations(:point_annotation)
    annotation.update!(viewport: :desktop)
    @screenshot_image.update!(status: :pending)
    assert_nil annotation.crop
  end

  test "CACHE_VERSION is set so deploys can invalidate old crops" do
    assert_equal 2, AnnotationCropService::CACHE_VERSION,
      "Bump CACHE_VERSION whenever the crop algorithm or record type changes"
  end
end
