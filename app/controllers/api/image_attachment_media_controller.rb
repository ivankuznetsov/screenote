# frozen_string_literal: true

module Api
  # Bearer-authenticated attachment delivery for agents and the CLI.
  #
  # Three things must hold on every request: a valid bearer principal with the
  # read scope, an unexpired purpose token minted for this exact attachment,
  # and live access to the project that still owns the message. The token alone
  # is never authority — revoking a credential or a membership takes effect on
  # the next byte request.
  class ImageAttachmentMediaController < Api::BaseController
    include BlobStreaming

    def show
      return unless require_scope!(AuthenticatedPrincipal::READ_SCOPE)

      attachment = authorized_attachment
      return unless attachment

      stream_blob(attachment.image.blob)
    end

    private

    def authorized_attachment
      attachment = ImageAttachment.find_by_token_for(
        ImageAttachment::MEDIA_TOKEN_PURPOSE, params[:token].to_s
      )
      return deny unless attachment
      return deny unless attachment.id.to_s == params[:id].to_s
      return deny unless attachment.state_ready? && attachment.image.attached?
      return deny unless attachment.submitted? && attachment.parent.present?
      return deny unless current_principal.project_access?(attachment.project)

      attachment
    end

    def deny
      render_error("Attachment is not available", code: "not_found", status: :not_found)
      nil
    end
  end
end
