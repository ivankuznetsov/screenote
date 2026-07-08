# frozen_string_literal: true

module Api
  class BaseController < ActionController::API
    before_action :authenticate_api_key!

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

    def authenticate_api_key!
      token = extract_bearer_token
      api_key = ApiKey.active.find_by_token(token)

      if api_key.nil?
        render_error("Invalid or missing API key", code: "unauthorized", status: :unauthorized)
        return
      end

      api_key.touch_last_used!
      @current_api_key = api_key
      @current_project = api_key.project
    end

    def extract_bearer_token
      header = request.headers["Authorization"]
      header&.match(/\ABearer\s+(.+)\z/)&.captures&.first
    end

    def require_current_project!(project_id)
      return current_project if project_id.blank?
      return current_project if project_id.to_s == current_project.id.to_s

      render_error("Project is not accessible with this API key", code: "forbidden", status: :forbidden)
      nil
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

    attr_reader :current_api_key, :current_project
  end
end
