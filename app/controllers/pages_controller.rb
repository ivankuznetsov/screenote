# frozen_string_literal: true

class PagesController < ApplicationController
  skip_before_action :require_authentication, only: [ :landing ]

  layout "landing", only: [ :landing ]

  def landing
    redirect_to dashboard_path if Current.user
  end

  def help
  end
end
