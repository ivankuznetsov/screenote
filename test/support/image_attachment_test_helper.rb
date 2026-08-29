# frozen_string_literal: true

require "tempfile"

module ImageAttachmentTestHelper
  private

  def image_bytes(format: "png", width: 8, height: 8)
    require "vips"
    Tempfile.create([ "screenote-test-", ".#{format}" ]) do |file|
      file.binmode
      Vips::Image.black(width, height).add(64).cast(:uchar).bandjoin([ 128, 200 ]).write_to_file(file.path)
      file.rewind
      file.read
    end
  end

  def build_batch(user: users(:alice), project: projects(:alice_project))
    ImageAttachmentBatch.create!(user: user, project: project)
  end

  def ingest_image(batch:, client_key: "key-#{SecureRandom.hex(4)}", bytes: nil, format: "png",
    declared_content_type: "image/png", filename: nil, declared_length: nil)
    bytes ||= image_bytes(format: format)
    ImageAttachments::Ingest.call(
      batch: batch,
      io: StringIO.new(bytes),
      client_key: client_key,
      declared_content_type: declared_content_type,
      declared_length: declared_length,
      filename: filename
    ).attachment
  end
end
