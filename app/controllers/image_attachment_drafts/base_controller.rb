# frozen_string_literal: true

module ImageAttachmentDrafts
  # Browser-only draft APIs. Authoring attachments is a session capability: the
  # standard forgery protection stays on, every request is scoped through the
  # signed-in user's current membership, and a draft that belongs to somebody
  # else is indistinguishable from one that does not exist.
  class BaseController < ApplicationController
    RATE_LIMIT = 120
    RATE_LIMIT_WINDOW = 1.hour
    DRAFT_RATE_LIMIT_STORE = Screenote::RateLimitStore.new(store: -> { cache_store })
    # One account budget and one address budget for the whole draft surface.
    # Without an explicit scope Rails keys each limit by controller path, which
    # would give batches and attachments a separate allowance apiece and double
    # what an account can actually spend.
    RATE_LIMIT_SCOPE = "image_attachment_drafts"

    # Authentication is inherited from ApplicationController and runs first, so
    # the account bucket is always keyed by a real signed-in identity rather
    # than by a shared anonymous one.
    rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW,
      by: -> { "user:#{Current.user.id}" },
      with: -> { render_error("Too many upload requests. Try again later.", code: "rate_limited", status: :too_many_requests) },
      store: DRAFT_RATE_LIMIT_STORE,
      scope: RATE_LIMIT_SCOPE
    rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW,
      by: -> { "ip:#{request.remote_ip}" },
      with: -> { render_error("Too many upload requests. Try again later.", code: "rate_limited", status: :too_many_requests) },
      store: DRAFT_RATE_LIMIT_STORE,
      scope: RATE_LIMIT_SCOPE

    rescue_from ImageAttachments::Error, with: :render_service_error
    rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable

    private

    def find_batch!
      public_id = params[:batch_public_id].presence || params[:public_id]
      batch = ImageAttachmentBatch.find_by(public_id: public_id.to_s)

      # A foreign or unknown draft is a 404, never a 403: sequential attachment
      # IDs and guessed batch IDs must not confirm that anything exists.
      raise ActiveRecord::RecordNotFound unless batch
      raise ActiveRecord::RecordNotFound unless batch.user_id == Current.user.id
      raise ActiveRecord::RecordNotFound unless member_of?(batch.project_id)

      batch
    end

    def find_project!
      project = Current.user.projects.find_by(id: params[:project_id])
      raise ActiveRecord::RecordNotFound unless project

      project
    end

    def member_of?(project_id)
      Current.user.projects.exists?(id: project_id)
    end

    def render_batch(batch, status: :ok)
      render json: ImageAttachments::DraftPresenter.batch(batch), status: status
    end

    def render_attachment(attachment, status: :ok)
      render json: { attachment: ImageAttachments::DraftPresenter.attachment(attachment) }, status: status
    end

    def render_service_error(error)
      render_error(error.message, code: error.code, status: error.status, retryable: error.retryable?)
    end

    def render_error(message, code:, status:, retryable: false)
      render json: { error: { code: code, message: message, retryable: retryable } }, status: status
    end

    def render_rate_limiter_unavailable(_error)
      render_error("Uploads are temporarily unavailable. Try again shortly.",
        code: "rate_limiter_unavailable", status: :service_unavailable, retryable: true)
    end

    def not_found
      render_error("Not found", code: "not_found", status: :not_found)
    end
  end
end
