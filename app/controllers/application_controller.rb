# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include RailsSimpleAuth::Controllers::Concerns::Authentication
  include RailsSimpleAuth::Controllers::Concerns::SessionManagement

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :require_authentication
end
