# frozen_string_literal: true

require "test_helper"

class ImageDecoderLimitsTest < ActiveSupport::TestCase
  test "libvips process resources remain bounded" do
    assert_operator ImageDecoding::Guard::CONCURRENCY, :<=, ImageDecoding::Guard::MAX_CONCURRENCY
    assert_equal 1, Vips.concurrency
    assert_operator Vips.cache_max, :<=, 100
    assert_operator Vips.cache_max_mem, :<=, 64.megabytes
    assert_operator Vips.cache_max_files, :<=, 20
  end

  test "automatic Active Storage analysis passes through the decoder guard" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(file_fixture("test_image.png").binread),
      filename: "guarded.png",
      content_type: "image/png"
    )
    calls = 0
    original = ImageDecoding::Guard.method(:synchronize)
    ImageDecoding::Guard.define_singleton_method(:synchronize) do |**_options, &operation|
      calls += 1
      operation.call
    end

    ActiveStorage::AnalyzeJob.perform_now(blob)

    assert_equal 1, calls
    assert blob.reload.analyzed?
  ensure
    ImageDecoding::Guard.define_singleton_method(:synchronize, original) if original
    blob&.purge
  end
end
