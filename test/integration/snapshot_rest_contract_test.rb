# frozen_string_literal: true

require "test_helper"

class SnapshotRestContractTest < ActionDispatch::IntegrationTest
  ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"

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
end
