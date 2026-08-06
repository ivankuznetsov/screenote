# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include RailsSimpleAuth::Controllers::Concerns::Authentication
  include ScreenoteSessionManagement
  include PageWorkspaceNavigation

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :require_authentication
  before_action :preload_subscription, if: -> { Screenote::Deployment.current.billing? }

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private

  def preload_subscription
    Current.user&.subscription # triggers load, cached by ActiveRecord for rest of request
  end

  def not_found
    respond_to do |format|
      format.html { render html: File.read(Rails.root.join("public/404.html")).html_safe, layout: false, status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end
end
