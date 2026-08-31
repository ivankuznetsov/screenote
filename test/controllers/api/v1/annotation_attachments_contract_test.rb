# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class AnnotationAttachmentsContractTest < ActionDispatch::IntegrationTest
      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
      BOB_TOKEN = "sk_proj_test_bob_key_0000000000000000000000000"

      setup do
        require_vips!
        @user = users(:alice)
        @project = projects(:alice_project)
        @annotation = annotations(:point_annotation)
      end

      test "the detail read exposes attachments on the root and every comment" do
        root = attach_to(@annotation, alt_text: "The disabled save button")
        comment = @annotation.annotation_comments.create!(user: @user, body: "Here is the crop")
        reply_attachment = attach_to(comment)

        get_detail

        assert_response :success
        body = response.parsed_body
        assert_equal [ root.id ], body.fetch("attachments").map { |item| item["id"] }
        assert_equal "The disabled save button", body.dig("attachments", 0, "alt_text")
        assert_equal(
          [ reply_attachment.id ],
          body.fetch("comments").find { |item| item["id"] == comment.id }.fetch("attachments").map { |i| i["id"] }
        )
      end

      test "attachments are always present as an array" do
        @annotation.annotation_comments.create!(user: @user, body: "No images here")

        get_detail

        assert_equal [], response.parsed_body.fetch("attachments")
        assert(response.parsed_body.fetch("comments").all? { |item| item.fetch("attachments") == [] })
      end

      test "every attachment carries the canonical object" do
        attach_to(@annotation)

        get_detail

        attachment = response.parsed_body.fetch("attachments").sole
        assert_equal(
          %w[alt_text height id media_type size url url_expires_at width],
          attachment.keys.sort
        )
        assert_match %r{/api/media/image_attachments/\d+\?token=}, attachment.fetch("url")
      end

      test "url expiry matches the five minute purpose token" do
        attach_to(@annotation)

        freeze_time do
          get_detail

          assert_equal ImageAttachment::MEDIA_TOKEN_EXPIRY.from_now.iso8601,
            response.parsed_body.dig("attachments", 0, "url_expires_at")
        end
      end

      test "no storage key or filename is exposed" do
        attachment = attach_to(@annotation)

        get_detail

        assert_not response.body.include?(attachment.image.blob.key)
        assert_not response.body.include?("service_name")
      end

      # The comment object has one shape across every endpoint that returns it.
      # A write endpoint mints no media URLs and its comment can never carry
      # attachments, so it answers the canonical empty array rather than
      # omitting the key.
      test "write endpoints return a comment with an empty attachments array" do
        post api_v1_annotation_comments_path(@annotation),
          params: { body: "Taking a look", project_id: @project.id },
          headers: bearer_headers

        assert_response :created
        assert_equal [], response.parsed_body.dig("comment", "attachments")
      end

      test "resolution endpoints return a comment with an empty attachments array" do
        post api_v1_annotation_resolve_path(@annotation),
          params: { project_id: @project.id },
          headers: bearer_headers

        assert_response :success
        assert_equal [], response.parsed_body.dig("comment", "attachments")
      end

      test "the list read stays metadata light" do
        attach_to(@annotation)

        get api_v1_screenshot_annotations_path(@annotation.screenshot, project_id: @project.id),
          headers: bearer_headers

        assert_response :success
        assert(response.parsed_body.fetch("annotations").none? { |item| item.key?("attachments") })
      end

      # A fixed ceiling would pass an N+1 that only shows up at scale, so the
      # budget is measured against itself: adding attachments to the root and
      # to a comment must not add a single query.
      test "detail reads do not scale queries with attachment count" do
        attach_to(@annotation)
        comment = @annotation.annotation_comments.create!(user: @user, body: "Reply")
        attach_to(comment)
        get_detail
        baseline = capture_app_queries { get_detail }.size

        2.times { attach_to(@annotation) }
        2.times { attach_to(comment) }
        get_detail

        assert_equal baseline, capture_app_queries { get_detail }.size,
          "detail reads must not scale queries with attachment count"
      end

      private

      def get_detail
        get api_v1_annotation_path(@annotation, project_id: @project.id), headers: bearer_headers
      end

      def bearer_headers
        { "Authorization" => "Bearer #{ALICE_TOKEN}" }
      end

      def attach_to(parent, alt_text: nil)
        batch = build_batch(user: @user, project: @project)
        attachment = ingest_image(batch: batch)
        attachment.update!(alt_text: alt_text) if alt_text
        ImageAttachments::ClaimBatch.call(batch: batch, user: @user, project: @project, parent_type: parent.class) { parent }
        attachment.reload
      end
    end
  end
end
