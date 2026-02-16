# frozen_string_literal: true

module Api
  class BaseController < ActionController::API
    before_action :authenticate_api_key!

    private

    def authenticate_api_key!
      token = extract_bearer_token
      api_key = ApiKey.active.find_by_token(token)

      if api_key.nil?
        render json: { error: "Invalid or missing API key" }, status: :unauthorized
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

    attr_reader :current_api_key, :current_project
  end
end
