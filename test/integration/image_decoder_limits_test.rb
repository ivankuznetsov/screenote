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

  # One draft batch retrying while its earlier upload is still decoding must not
  # be able to hold every global slot and answer screenshot work with
  # `decoder_busy`.
  test "a keyed decode runs one at a time and leaves the other global slot free" do
    entered = Queue.new
    release = Queue.new
    key = "image_attachment_batch:test"

    holder = Thread.new do
      ImageDecoding::Guard.synchronize(key: key) do
        entered << true
        release.pop
      end
    end
    entered.pop

    assert_raises(ImageDecoding::Guard::Busy) do
      ImageDecoding::Guard.synchronize(key: key, timeout: 0) { flunk "a second decode took the same key" }
    end

    # Another key still gets a slot: the serialization is per key, not global.
    assert ImageDecoding::Guard.synchronize(key: "other", timeout: 0) { true }
  ensure
    release << true
    holder&.join(5)
  end

  test "a keyed decode releases its key for the next caller" do
    key = "image_attachment_batch:sequential"

    2.times { assert ImageDecoding::Guard.synchronize(key: key, timeout: 0) { true } }
    assert_empty ImageDecoding::Guard::KEYED
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
