# frozen_string_literal: true

module Api
  module V1
    class ImageCommentsController < Api::BaseController
      include Api::ImageUploadRateLimiting

      CAPABILITY = "image-comments-v1"
      UPLOAD_RATE_LIMIT = Api::ImageUploadRateLimiting::UPLOAD_RATE_LIMIT
      IDEMPOTENCY_KEY = ImageAttachments::CreateApiComment::IDEMPOTENCY_KEY
      SHA256 = ImageAttachments::CreateApiComment::SHA256

      before_action :mark_capability
      before_action :validate_header_envelope

      rate_limit_image_uploads only: :create

      rescue_from ImageAttachments::Error, with: :render_image_attachment_error

      def create
        return unless require_scope!(AuthenticatedPrincipal::WRITE_SCOPE)

        project_id = scalar_param(:project_id)
        return if performed?
        project = require_current_project!(project_id)
        return unless project

        annotation = Api::V1::ProjectScope.annotations(project).find_by(
          id: request.path_parameters[:annotation_id]
        )
        unless annotation
          render_error("Annotation not found", code: "annotation_not_found", status: :not_found)
          return
        end

        body = scalar_param(:body)
        return if performed?
        invalid!("invalid_body") if body.blank?

        images = params[:images]
        invalid!("missing_image") unless images.is_a?(Array) && images.any?
        invalid!("too_many_images") unless images.one?
        upload = images.sole
        invalid!("missing_image") unless upload.is_a?(ActionDispatch::Http::UploadedFile)

        result = ImageAttachments::CreateApiComment.call(
          annotation:,
          project:,
          principal: current_principal,
          body:,
          io: upload.tempfile,
          idempotency_key: request.headers["Idempotency-Key"],
          expected_sha256: request.headers["Screenote-Image-SHA256"],
          declared_content_type: upload.content_type,
          declared_length: upload.size,
          filename: upload.original_filename
        )

        render json: Api::V1::ContractSerializer.image_comment(result),
          status: result.created? ? :created : :ok
      end

      private

      def mark_capability
        response.set_header("Screenote-API-Capability", CAPABILITY)
      end

      def validate_header_envelope
        key = request.headers["Idempotency-Key"].to_s
        invalid!("invalid_idempotency_key") unless IDEMPOTENCY_KEY.match?(key)

        digest = request.headers["Screenote-Image-SHA256"].to_s
        invalid!("content_digest_mismatch", status: :conflict) if digest.present? && !SHA256.match?(digest)
      end

      def scalar_param(name)
        value = params[name]
        return value if value.is_a?(String) || value.is_a?(Integer)
        return nil if value.nil?

        code = name == :body ? "invalid_body" : "invalid_project"
        render_error("Invalid #{name.to_s.humanize.downcase}", code:, status: :unprocessable_entity)
        nil
      end

      def upload_rate_limit_project_id
        current_api_key&.project_id || current_oauth_token&.project_id || "unbound"
      end

      def render_image_attachment_error(error)
        render_error(error.message, code: error.code, status: error.status)
      end

      def invalid!(code, status: :unprocessable_entity)
        raise ImageAttachments::Error.new(code: code, status: status)
      end
    end
  end
end
