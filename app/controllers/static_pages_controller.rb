# frozen_string_literal: true

class StaticPagesController < ApplicationController
  skip_before_action :require_authentication

  layout "landing", only: [ :landing ]

  def landing
    redirect_to dashboard_path if Current.user
  end

  def help
    @tools = ApplicationTool.descendants.sort_by(&:tool_name)
  end

  def terms; end

  def privacy; end
end
