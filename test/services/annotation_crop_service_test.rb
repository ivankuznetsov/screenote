# frozen_string_literal: true

require "test_helper"

class AnnotationCropServiceTest < ActiveSupport::TestCase
  setup do
    @screenshot = screenshots(:alice_screenshot)
    @screenshot.update!(width: 400, height: 300)
    @screenshot.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "test.png",
      content_type: "image/png"
    )
  end

  test "crops point annotation" do
    annotation = annotations(:point_annotation)

    result = AnnotationCropService.crop(@screenshot, annotation)
    assert result.present?, "Should return base64 encoded image"
    assert_nothing_raised { Base64.strict_decode64(result) }
  end

  test "crops region annotation" do
    annotation = annotations(:region_annotation)

    result = AnnotationCropService.crop(@screenshot, annotation)
    assert result.present?, "Should return base64 encoded image"
    assert_nothing_raised { Base64.strict_decode64(result) }
  end

  test "caches crop result" do
    annotation = annotations(:point_annotation)

    result1 = AnnotationCropService.crop(@screenshot, annotation)
    result2 = AnnotationCropService.crop(@screenshot, annotation)
    assert_equal result1, result2, "Cached result should be identical"
  end

  test "class method delegates to instance" do
    annotation = annotations(:point_annotation)

    service = AnnotationCropService.new(@screenshot, annotation)
    assert_equal service.crop, AnnotationCropService.crop(@screenshot, annotation)
  end
end
