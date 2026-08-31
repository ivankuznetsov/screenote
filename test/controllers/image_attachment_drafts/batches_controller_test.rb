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

    test "expired but unreclaimed batches still count toward the open cap" do
      ImageAttachmentBatch::MAX_OPEN_PER_USER.times do
        build_batch(user: @user, project: @project)
          .update_columns(last_activity_at: 30.hours.ago, expires_at: 6.hours.ago)
      end

      post image_attachment_draft_batches_path, params: { project_id: @project.id }, as: :json

      assert_response :unprocessable_entity
      assert_equal "too_many_open_batches", response.parsed_body.dig("error", "code")
    end

    test "opening a draft requires a CSRF token" do
      with_forgery_protection do
        post image_attachment_draft_batches_path, params: { project_id: @project.id }, as: :json

        assert_response :unprocessable_entity
      end
      assert_equal 0, @user.image_attachment_batches.count
    end

    test "resumes an existing batch" do
      batch = build_batch(user: @user, project: @project)

      get image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :success
      assert_equal batch.public_id, response.parsed_body["batch_id"]
    end

    # A create whose response is lost has to be retryable. Without an
    # idempotency key each retry spent one more of the six batches an account is
    # allowed, so a flaky connection could lock a person out of uploading.
    test "a repeated create with the same client key returns the same batch" do
      post image_attachment_draft_batches_path,
        params: { project_id: @project.id, client_key: "composer-abc123" }, as: :json
      assert_response :created
      first = response.parsed_body["batch_id"]

      assert_no_difference -> { ImageAttachmentBatch.count } do
        post image_attachment_draft_batches_path,
          params: { project_id: @project.id, client_key: "composer-abc123" }, as: :json
      end

      assert_response :success
      assert_equal first, response.parsed_body["batch_id"]
    end

    test "different client keys still open separate batches" do
      post image_attachment_draft_batches_path,
        params: { project_id: @project.id, client_key: "composer-aaaaaa" }, as: :json
      first = response.parsed_body["batch_id"]

      post image_attachment_draft_batches_path,
        params: { project_id: @project.id, client_key: "composer-bbbbbb" }, as: :json

      assert_response :created
      assert_not_equal first, response.parsed_body["batch_id"]
    end

    test "a client key whose batch expired opens a usable replacement" do
      post image_attachment_draft_batches_path,
        params: { project_id: @project.id, client_key: "composer-expired" }, as: :json
      stale = ImageAttachmentBatch.find_by!(public_id: response.parsed_body["batch_id"])
      stale.update_columns(last_activity_at: 30.hours.ago, expires_at: 1.minute.ago)

      post image_attachment_draft_batches_path,
        params: { project_id: @project.id, client_key: "composer-expired" }, as: :json

      assert_response :created
      assert_not ImageAttachmentBatch.exists?(stale.id)
      assert_predicate ImageAttachmentBatch.find_by!(public_id: response.parsed_body["batch_id"]), :usable?
    end

    test "a malformed client key is rejected" do
      post image_attachment_draft_batches_path,
        params: { project_id: @project.id, client_key: "no" }, as: :json

      assert_response :unprocessable_entity
      assert_equal "invalid_client_key", response.parsed_body.dig("error", "code")
    end

    # Media, upload, and claim all reject an expired batch, so answering resume
    # with 200 and its ready rows would only re-enable a post that is certain to
    # fail with `batch_unusable`.
    test "an expired batch cannot be resumed" do
      batch = build_batch(user: @user, project: @project)
      ingest_image(batch: batch)
      batch.update_columns(last_activity_at: 30.hours.ago, expires_at: 1.minute.ago)

      get image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :unprocessable_entity
      assert_equal "batch_unusable", response.parsed_body.dig("error", "code")
    end

    test "a claimed batch cannot be resumed" do
      batch = build_batch(user: @user, project: @project)
      batch.update!(state: :claimed, claimed_annotation: annotations(:point_annotation))

      get image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :unprocessable_entity
      assert_equal "batch_unusable", response.parsed_body.dig("error", "code")
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

    test "cancelling discards the draft and frees its slot against the open cap" do
      batch = build_batch(user: @user, project: @project)
      attachment = ingest_image(batch: batch)
      (ImageAttachmentBatch::MAX_OPEN_PER_USER - 1).times { build_batch(user: @user, project: @project) }

      delete image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :no_content
      assert_not ImageAttachmentBatch.exists?(batch.id)
      assert_not ImageAttachment.exists?(attachment.id)

      post image_attachment_draft_batches_path, params: { project_id: @project.id }, as: :json

      assert_response :created
    end

    test "discarding is idempotent and never touches a claimed batch" do
      batch = build_batch(user: @user, project: @project)
      attachment = ingest_image(batch: batch)
      ImageAttachments::ClaimBatch.call(batch: batch, user: @user, project: @project, parent_type: Annotation) do
        annotations(:point_annotation)
      end

      delete image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :no_content
      assert_predicate batch.reload, :state_claimed?
      assert_equal annotations(:point_annotation).id, attachment.reload.annotation_id

      delete image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :no_content
    end

    test "another member cannot discard a guessed batch" do
      batch = build_batch(user: @user, project: @project)
      @project.project_memberships.find_or_create_by!(user: users(:bob)) { |m| m.role = :member }
      delete session_path
      sign_in users(:bob)

      delete image_attachment_draft_batch_path(batch.public_id), as: :json

      assert_response :not_found
      assert ImageAttachmentBatch.exists?(batch.id)
    end

    test "discarding a draft requires a CSRF token" do
      batch = build_batch(user: @user, project: @project)

      with_forgery_protection do
        delete image_attachment_draft_batch_path(batch.public_id), as: :json

        assert_response :unprocessable_entity
      end
      assert ImageAttachmentBatch.exists?(batch.id)
    end
  end
end
