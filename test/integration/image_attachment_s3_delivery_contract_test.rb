# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require_relative "../support/s3_contract_helper"

# Disk-backed delivery tests prove the route, header, and token policy, but they
# cannot prove the application streams provider bytes itself: a Disk service has
# no presigned URL to leak and no remote host to redirect to. This runs the same
# protected routes with the whole application pointed at a real object store, so
# "the bytes come through the application, never through the provider" is
# executed rather than inferred.
class ImageAttachmentS3DeliveryContractTest < ActionDispatch::IntegrationTest
  include S3ContractHelper

  setup do
    require_s3_contract!
    require_vips!
    @user = users(:alice)
    @project = projects(:alice_project)
    @annotation = annotations(:point_annotation)
    @client = Aws::S3::Client.new(client_options)
    @client.create_bucket(bucket: bucket)
  rescue Aws::S3::Errors::BucketAlreadyOwnedByYou
    nil
  end

  teardown do
    next unless defined?(@client) && @client

    @client.list_objects_v2(bucket: bucket, prefix: prefix).contents.each do |object|
      @client.delete_object(bucket: bucket, key: object.key)
    end
  end

  test "the session route streams provider bytes without ever naming the provider" do
    with_s3_active_storage do
      attachment = submitted_attachment
      assert_stored_on_provider attachment

      sign_in(@user)
      get image_attachment_media_path(attachment, :original)

      assert_response :ok
      assert_equal attachment.media_type, response.media_type
      assert_equal @bytes, response.body.b
      assert_no_provider_location
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    end
  end

  test "the session route streams a warmed variant from the provider" do
    with_s3_active_storage do
      attachment = submitted_attachment
      ImageAttachment::THUMBNAIL_VARIANT_NAMES.each { |name| attachment.image.variant(name).processed }

      sign_in(@user)
      get image_attachment_media_path(attachment, :attachment_thumb_1x)

      assert_response :ok
      assert_no_provider_location
      assert_predicate response.body.bytesize, :positive?
      assert_equal "image/png", response.media_type
    end
  end

  test "the application serves byte ranges itself instead of handing back a provider URL" do
    with_s3_active_storage do
      attachment = submitted_attachment

      sign_in(@user)
      get image_attachment_media_path(attachment, :original), headers: { "Range" => "bytes=0-15" }

      assert_response :partial_content
      assert_equal @bytes.byteslice(0, 16), response.body.b
      assert_no_provider_location
    end
  end

  test "the bearer route streams provider bytes and its purpose token still expires in five minutes" do
    with_s3_active_storage do
      attachment = submitted_attachment
      token = attachment.generate_token_for(ImageAttachment::MEDIA_TOKEN_PURPOSE)

      get api_image_attachment_media_path(attachment, token: token), headers: bearer_headers

      assert_response :ok
      assert_equal @bytes, response.body.b
      assert_no_provider_location

      travel ImageAttachment::MEDIA_TOKEN_EXPIRY + 1.second do
        get api_image_attachment_media_path(attachment, token: token), headers: bearer_headers

        assert_response :not_found
        assert_no_provider_location
      end
    end
  end

  test "an API image comment creates once, replays, and streams its provider bytes" do
    with_s3_active_storage do
      @bytes = image_bytes(width: 64, height: 48)
      created = create_api_comment
      replayed = create_api_comment

      assert_equal "created", created.operation
      assert_equal "replayed", replayed.operation
      assert_equal created.comment.id, replayed.comment.id
      assert_equal created.attachment.id, replayed.attachment.id
      assert_stored_on_provider created.attachment

      token = created.attachment.generate_token_for(ImageAttachment::MEDIA_TOKEN_PURPOSE)
      get api_image_attachment_media_path(created.attachment, token: token), headers: bearer_headers

      assert_response :ok
      assert_equal @bytes, response.body.b
      assert_no_provider_location
    end
  end

  test "a database failure after API provider staging removes the unowned object" do
    with_s3_active_storage do
      @bytes = image_bytes(width: 64, height: 48)
      before = provider_keys
      before_counts = [ AnnotationComment.count, ImageAttachment.count, ActiveStorage::Blob.count ]

      error = with_singleton_method_stub(
        ImageAttachment, :transaction, ->(*) { raise "database unavailable after staging" }
      ) do
        assert_raises(ImageAttachments::Error) { create_api_comment(key: "s3_failure_cleanup_key_1234") }
      end

      assert_equal "upload_failed", error.code
      assert_equal before, provider_keys
      assert_equal before_counts, [ AnnotationComment.count, ImageAttachment.count, ActiveStorage::Blob.count ]
    end
  end

  test "a revoked membership loses provider bytes on the next request" do
    with_s3_active_storage do
      attachment = submitted_attachment
      @project.project_memberships.find_or_create_by!(user: users(:bob)) { |m| m.role = :member }
      sign_in(users(:bob))
      get image_attachment_media_path(attachment, :original)
      assert_response :ok

      @project.project_memberships.where(user: users(:bob)).delete_all

      get image_attachment_media_path(attachment, :original)

      assert_response :not_found
      assert_no_provider_location
    end
  end

  private

  ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"

  def bearer_headers
    { "Authorization" => "Bearer #{ALICE_TOKEN}" }
  end

  def submitted_attachment
    @bytes = image_bytes(width: 64, height: 48)
    batch = build_batch(user: @user, project: @project)
    attachment = ingest_image(batch: batch, bytes: @bytes)
    ImageAttachments::ClaimBatch.call(
      batch: batch, user: @user, project: @project, parent_type: Annotation
    ) { @annotation }
    attachment.reload
  end

  def create_api_comment(key: "s3_image_comment_key_123456")
    ImageAttachments::CreateApiComment.call(
      annotation: @annotation,
      project: @project,
      principal: AuthenticatedPrincipal.for_api_key(api_keys(:alice_key)),
      body: "Use this S3 reference",
      io: StringIO.new(@bytes),
      idempotency_key: key,
      expected_sha256: Digest::SHA256.hexdigest(@bytes),
      declared_content_type: "image/png",
      declared_length: @bytes.bytesize,
      filename: "reference.png"
    )
  end

  def provider_keys
    @client.list_objects_v2(bucket: bucket, prefix: prefix).contents.map(&:key).sort
  end

  def with_singleton_method_stub(object, method_name, replacement)
    singleton = object.singleton_class
    original = object.method(method_name)
    singleton.define_method(method_name, replacement)
    yield
  ensure
    singleton&.define_method(method_name, original)
  end

  # Without this the suite could pass against the Disk service it exists to
  # replace, so the object has to be readable through the provider client.
  def assert_stored_on_provider(attachment)
    key = attachment.image.blob.key

    assert_equal "s3_contract", attachment.image.blob.service_name
    assert_equal @bytes, @client.get_object(bucket: bucket, key: "#{prefix}/#{key}").body.read.b
  end

  def assert_no_provider_location
    assert_nil response.headers["Location"]
    assert_not response.redirect?
    refute_includes response.headers.to_h.values.map(&:to_s).join(" "), ENV.fetch("SCREENOTE_S3_ENDPOINT")
    refute_includes response.body.to_s, "X-Amz-Signature"
  end
end
