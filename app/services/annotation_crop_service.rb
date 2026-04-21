# frozen_string_literal: true

# Crops the region around an annotation from the matching ScreenshotImage.
# Callers should prefer `screenshot_image.crop_for(annotation)` (see
# ScreenshotImage#crop_for) which delegates here.
class AnnotationCropService
  # Bump when the crop algorithm changes or when the underlying image record
  # type changes (PR-2: Screenshot -> ScreenshotImage). Participates in the
  # cache key so in-flight jobs and already-cached crops from the previous
  # generation don't serve incorrect data after deploy.
  CACHE_VERSION = 2

  POINT_CROP_SIZE = 200
  REGION_PADDING = 50
  MAX_DIMENSION = 1072

  def initialize(screenshot_image, annotation)
    @screenshot_image = screenshot_image
    @annotation = annotation
  end

  def self.crop(screenshot_image, annotation)
    new(screenshot_image, annotation).crop
  end

  def crop
    cache_key = [
      "annotation_crop/v#{CACHE_VERSION}",
      @annotation.id,
      @annotation.updated_at.to_i,
      @screenshot_image.image.blob.checksum
    ].join("/")

    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      @screenshot_image.image.blob.open do |tempfile|
        image = ImageProcessing::Vips.source(tempfile)
        result = @annotation.point? ? crop_point(image) : crop_region(image)
        Base64.strict_encode64(File.binread(result.path))
      end
    end
  end

  private

  def crop_point(image)
    cx = (@annotation.x_percent / 100.0 * @screenshot_image.width).round
    cy = (@annotation.y_percent / 100.0 * @screenshot_image.height).round
    half = POINT_CROP_SIZE / 2

    left = [ cx - half, 0 ].max
    top  = [ cy - half, 0 ].max
    w    = [ POINT_CROP_SIZE, @screenshot_image.width - left ].min
    h    = [ POINT_CROP_SIZE, @screenshot_image.height - top ].min

    image
      .crop(left, top, w, h)
      .resize_to_limit(MAX_DIMENSION, MAX_DIMENSION)
      .call
  end

  def crop_region(image)
    x = (@annotation.x_percent / 100.0 * @screenshot_image.width).round
    y = (@annotation.y_percent / 100.0 * @screenshot_image.height).round
    w = (@annotation.width_percent / 100.0 * @screenshot_image.width).round
    h = (@annotation.height_percent / 100.0 * @screenshot_image.height).round

    left = [ x - REGION_PADDING, 0 ].max
    top  = [ y - REGION_PADDING, 0 ].max
    crop_w = [ w + (REGION_PADDING * 2), @screenshot_image.width - left ].min
    crop_h = [ h + (REGION_PADDING * 2), @screenshot_image.height - top ].min

    image
      .crop(left, top, crop_w, crop_h)
      .resize_to_limit(MAX_DIMENSION, MAX_DIMENSION)
      .call
  end
end
