# frozen_string_literal: true

require "test_helper"

class SnapshotRestContractTest < ActionDispatch::IntegrationTest
  ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"

  setup do
    @controller_class = Api::V1::ScreenshotImagesController
    @original_upload_rate_limit_backend = @controller_class.cache_store
    @controller_class.cache_store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    @controller_class.cache_store = @original_upload_rate_limit_backend
  end

  test "preparation response exposes the stable CLI recovery contract without local references" do
    project = projects(:alice_project)
    post api_v1_project_snapshots_path(project),
      params: snapshot_manifest_payload,
      headers: { "Authorization" => "Bearer #{ALICE_TOKEN}" },
      as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal %w[entries git_commit manifest_digest operation project_id review_url snapshot_id state taken_at], body.keys.sort
    assert_equal %w[attached content_sha256 image_id manifest_entry_digest mime_type page page_id screenshot_id state status title viewport],
      body.fetch("entries").first.keys.sort
    assert_not_includes response.body, "file_ref"
    assert_not_includes response.body, "captures/"
  end

  test "authenticated image upload exposes the stable progress contract" do
    bytes = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
    entry = snapshot_entry(page: "Upload contract", viewport: :desktop, seed: "upload-contract")
    entry[:content_sha256] = Digest::SHA256.hexdigest(bytes)
    project = projects(:alice_project)
    snapshot = Snapshots::PrepareUpload.call(
      project: project,
      payload: snapshot_manifest_payload(entries: [ entry ])
    ).snapshot
    image = snapshot.screenshot_images.first

    put api_v1_project_screenshot_image_path(project, image),
      headers: { "Authorization" => "Bearer #{ALICE_TOKEN}", "Content-Type" => "image/png" },
      env: { "RAW_POST_DATA" => bytes }

    assert_response :success
    assert_equal %w[attached image_id operation screenshot_id snapshot_id snapshot_state state status viewport], response.parsed_body.keys.sort
    assert_equal "uploaded", response.parsed_body["operation"]
    assert_equal "processing", response.parsed_body["state"]
  end
end
