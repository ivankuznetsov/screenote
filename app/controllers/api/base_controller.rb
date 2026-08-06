# frozen_string_literal: true

module Api
  class BaseController < ActionController::API
    before_action :authenticate_bearer!

    rescue_from ActiveRecord::RecordInvalid do |e|
      render_error(
        e.record.errors.full_messages.join(", "),
        code: "validation_failed",
        status: :unprocessable_entity,
        details: e.record.errors.full_messages
      )
    end

    rescue_from ActiveRecord::RecordNotFound do |e|
      render_error(e.message, code: "not_found", status: :not_found)
    end

    private

    def authenticate_bearer!
      token = extract_bearer_token
      result = Api::BearerAuthenticator.call(token)

      if result.nil?
        render_error("Invalid or missing bearer token", code: "unauthorized", status: :unauthorized)
        return
      end

      @current_principal = result
      @current_project = result.project
    end

    def extract_bearer_token
      header = request.headers["Authorization"]
      header&.match(/\ABearer\s+(.+)\z/)&.captures&.first
    end

    def require_current_project!(project_id)
      if oauth_authenticated? && project_id.blank?
        render_error("Project is required", code: "missing_project", status: :unprocessable_entity)
        return nil
      end

      project = Api::V1::ProjectScope.resolve_project(current_principal, project_id)
      if project
        @current_project = project
        return project
      end

      credential_name = api_key_authenticated? ? "API key" : "OAuth token"
      render_error("Project is not accessible with this #{credential_name}", code: "forbidden", status: :forbidden)
      nil
    end

    def require_scope!(scope)
      return true if current_principal.allows_scope?(scope)

      render_error("OAuth token is missing required scope #{scope}", code: "insufficient_scope", status: :forbidden)
      false
    end

    def api_key_authenticated?
      current_principal.api_key?
    end

    def oauth_authenticated?
      current_principal.oauth?
    end

    def pagination_params
      limit = integer_param(:limit, 50).clamp(1, 100)
      offset = [ integer_param(:offset, 0), 0 ].max

      [ limit, offset ]
    end

    def serializer_url_options
      Screenote::Deployment.current.url_options
    end

    # Coerce only scalar pagination values; structured params such as
    # `limit[x]=1` or `offset[]=2` are treated as absent rather than raising.
    def integer_param(key, default)
      value = params[key]
      return default unless value.is_a?(String) || value.is_a?(Integer)

      value.to_i
    end

    def render_error(message, code:, status:, details: nil)
      payload = { error: message, code: code }
      payload[:details] = details if details
      render json: payload, status: status
    end

    attr_reader :current_principal, :current_project

    delegate :api_key, :oauth_token, :user,
      to: :current_principal,
      prefix: :current,
      allow_nil: true
  end
end
