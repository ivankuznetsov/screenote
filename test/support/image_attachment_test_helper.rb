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

  # Limits are constants so that nothing can widen them at runtime; tests that
  # need a narrower ceiling swap it back afterwards.
  def stub_const(owner, name, value)
    original = owner.const_get(name)
    owner.send(:remove_const, name)
    owner.const_set(name, value)
    yield
  ensure
    owner.send(:remove_const, name)
    owner.const_set(name, original)
  end

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
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
