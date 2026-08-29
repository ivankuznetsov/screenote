# frozen_string_literal: true

require "test_helper"

module ImageAttachmentDrafts
  class BatchesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:alice)
      @project = projects(:alice_project)
      sign_in @user
    end

    test "creates an isolated batch for a project the user belongs to" do
      post image_attachment_draft_batches_path, params: { project_id: @project.id }, as: :json

      assert_response :created
      body = response.parsed_body
      assert_equal @project.id, body["project_id"]
      assert_equal "open", body["state"]
      assert_empty body["attachments"]
      assert_equal ImageAttachment::MAX_FILES, body.dig("limits", "max_files")
      assert_equal ImageAttachment::ALLOWED_CONTENT_TYPES, body.dig("limits", "accepted_media_types")
      assert_match ImageAttachmentBatch::PUBLIC_ID_FORMAT, body["batch_id"]
    end

    test "rejects a project the user does not belong to" do
      post image_attachment_draft_batches_path, params: { project_id: projects(:bob_project).id }, as: :json

      assert_response :not_found
      assert_equal "not_found", response.parsed_body.dig("error", "code")
    end

    test "requires a signed in user" do
      delete session_path

      post image_attachment_draft_batches_path, params: { project_id: @project.id }, as: :json

      assert_response :unauthorized
    end

    test "caps the number of simultaneously open batches" do
      ImageAttachmentBatch::MAX_OPEN_PER_USER.times { build_batch(user: @user, project: @project) }

      post image_attachment_draft_batches_path, params: { project_id: @project.id }, as: :json

      assert_response :unprocessable_entity
      assert_equal "too_many_open_batches", response.parsed_body.dig("error", "code")
    end

    test "caps total outstanding draft bytes independently of the scheduler" do
      batch = build_batch(user: @user, project: @project)
      per_file = ImageAttachment::MAX_FILE_SIZE
      (ImageAttachmentBatch::MAX_OUTSTANDING_DRAFT_BYTES / per_file.to_f).ceil.times do |index|
        batch.image_attachments.create!(
          user: @user, project: @project, client_key: "big-#{index}", state: :ready,
          media_type: "image/png", width: 1, height: 1, byte_size: per_file
        )
      end

      post image_attachment_draft_batches_path, params: { project_id: @project.id }, as: :json

      assert_response :unprocessable_entity
      assert_equal "draft_storage_exhausted", response.parsed_body.dig("error", "code")
    end

    test "resumes an existing batch" do
      batch = build_batch(user: @user, project: @project)

      get image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :success
      assert_equal batch.public_id, response.parsed_body["batch_id"]
    end

    test "another member cannot resume a guessed batch" do
      batch = build_batch(user: @user, project: @project)
      @project.project_memberships.find_or_create_by!(user: users(:bob)) { |m| m.role = :member }
      delete session_path
      sign_in users(:bob)

      get image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :not_found
    end

    test "a removed member loses access to their own draft" do
      batch = build_batch(user: @user, project: @project)
      @project.project_memberships.where(user: @user).delete_all

      get image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :not_found
    end
  end
end
