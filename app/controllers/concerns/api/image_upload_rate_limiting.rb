# frozen_string_literal: true

module Api
  module ImageUploadRateLimiting
    extend ActiveSupport::Concern

    UPLOAD_RATE_LIMIT = 250

    class_methods do
      def rate_limit_image_uploads(only:)
        store = Screenote::RateLimitStore.new(store: -> { cache_store })

        rate_limit to: UPLOAD_RATE_LIMIT, within: 1.hour, only: only,
          by: :upload_credential_rate_limit_identity,
          with: :render_upload_rate_limited,
          store: store,
          name: "credential"
        rate_limit to: UPLOAD_RATE_LIMIT, within: 1.hour, only: only,
          by: -> { "ip:#{request.remote_ip}" },
          with: :render_upload_rate_limited,
          store: store,
          name: "ip"

        rescue_from Screenote::RateLimitStore::Unavailable, with: :render_upload_rate_limit_unavailable
      end
    end

    private

    def upload_credential_rate_limit_identity
      credential = if current_api_key
        "api-key:#{current_api_key.id}"
      elsif current_oauth_token
        "oauth-token:#{current_oauth_token.id}"
      else
        "unauthenticated"
      end

      "#{credential}:project:#{upload_rate_limit_project_id}"
    end

    def upload_rate_limit_project_id
      bound_project_id = current_api_key&.project_id || current_oauth_token&.project_id
      return bound_project_id.to_s if bound_project_id

      raw_project_id = request.path_parameters[:project_id]
      Integer(raw_project_id.to_s, 10, exception: false)&.to_s || "invalid"
    end

    def render_upload_rate_limited
      response.set_header("Retry-After", 1.hour.to_i.to_s)
      render_error("Too many image uploads", code: "rate_limited", status: :too_many_requests)
    end

    def render_upload_rate_limit_unavailable
      response.set_header("Cache-Control", "no-store")
      response.set_header("Retry-After", Screenote::RateLimitFailureMiddleware::RETRY_AFTER)
      render_error(
        "Image upload throttling is temporarily unavailable",
        code: "rate_limit_unavailable",
        status: :service_unavailable
      )
    end
  end
end
