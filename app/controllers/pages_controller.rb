# frozen_string_literal: true

class PagesController < ApplicationController
  skip_before_action :require_authentication

  layout "landing"

  def landing
    redirect_to projects_path if Current.user
  end
end
