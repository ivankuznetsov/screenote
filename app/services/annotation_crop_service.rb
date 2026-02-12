# frozen_string_literal: true

class AnnotationCropService
  POINT_CROP_SIZE = 200
  REGION_PADDING = 50
  MAX_DIMENSION = 1072

  def initialize(screenshot, annotation)
    @screenshot = screenshot
    @annotation = annotation
  end

  def self.crop(screenshot, annotation)
    new(screenshot, annotation).crop
  end

  def crop
    cache_key = "annotation_crop/#{@annotation.id}/#{@screenshot.image.blob.checksum}"

    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      @screenshot.image.blob.open do |tempfile|
        image = ImageProcessing::Vips.source(tempfile)
        result = @annotation.point? ? crop_point(image) : crop_region(image)
        Base64.strict_encode64(File.binread(result.path))
      end
    end
  end

  private

  def crop_point(image)
    cx = (@annotation.x_percent / 100.0 * @screenshot.width).round
    cy = (@annotation.y_percent / 100.0 * @screenshot.height).round
    half = POINT_CROP_SIZE / 2

    left = [ cx - half, 0 ].max
    top  = [ cy - half, 0 ].max
    w    = [ POINT_CROP_SIZE, @screenshot.width - left ].min
    h    = [ POINT_CROP_SIZE, @screenshot.height - top ].min

    image
      .crop(left, top, w, h)
      .resize_to_limit(MAX_DIMENSION, MAX_DIMENSION)
      .call
  end

  def crop_region(image)
    x = (@annotation.x_percent / 100.0 * @screenshot.width).round
    y = (@annotation.y_percent / 100.0 * @screenshot.height).round
    w = (@annotation.width_percent / 100.0 * @screenshot.width).round
    h = (@annotation.height_percent / 100.0 * @screenshot.height).round

    left = [ x - REGION_PADDING, 0 ].max
    top  = [ y - REGION_PADDING, 0 ].max
    crop_w = [ w + (REGION_PADDING * 2), @screenshot.width - left ].min
    crop_h = [ h + (REGION_PADDING * 2), @screenshot.height - top ].min

    image
      .crop(left, top, crop_w, crop_h)
      .resize_to_limit(MAX_DIMENSION, MAX_DIMENSION)
      .call
  end
end
