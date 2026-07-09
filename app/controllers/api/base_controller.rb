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

      @current_api_key = result.api_key
      @current_oauth_token = result.oauth_token
      @current_user = result.user
      @current_project = result.api_key&.project
    end

    def extract_bearer_token
      header = request.headers["Authorization"]
      header&.match(/\ABearer\s+(.+)\z/)&.captures&.first
    end

    def require_current_project!(project_id)
      if api_key_authenticated?
        if current_project.present? && (project_id.blank? || project_id.to_s == current_project.id.to_s)
          return current_project
        end

        render_error("Project is not accessible with this API key", code: "forbidden", status: :forbidden)
        return nil
      end

      if project_id.blank?
        render_error("Project is required", code: "missing_project", status: :unprocessable_entity)
        return nil
      end

      project = Project.find_by(id: project_id)
      if project&.member?(current_user)
        @current_project = project
        return project
      end

      render_error("Project is not accessible with this OAuth token", code: "forbidden", status: :forbidden)
      nil
    end

    def require_scope!(scope)
      return true if api_key_authenticated?
      return true if oauth_scope?(scope)

      render_error("OAuth token is missing required scope #{scope}", code: "insufficient_scope", status: :forbidden)
      false
    end

    def api_key_authenticated?
      current_api_key.present?
    end

    def oauth_authenticated?
      current_oauth_token.present?
    end

    def oauth_scope?(scope)
      current_oauth_token&.scopes&.include?(scope.to_s)
    end

    def pagination_params
      limit = integer_param(:limit, 50).clamp(1, 100)
      offset = [ integer_param(:offset, 0), 0 ].max

      [ limit, offset ]
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

    attr_reader :current_api_key, :current_oauth_token, :current_user, :current_project
  end
end
