# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include RailsSimpleAuth::Controllers::Concerns::Authentication
  include RailsSimpleAuth::Controllers::Concerns::SessionManagement

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :require_authentication

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private

  def not_found
    respond_to do |format|
      format.html { render file: Rails.root.join("public/404.html"), layout: false, status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end
end
