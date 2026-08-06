# frozen_string_literal: true

class StaticPagesController < ApplicationController
  skip_before_action :require_authentication
  before_action :require_saas_legal!, only: %i[terms privacy]

  layout "landing", only: [ :landing ]

  def landing
    redirect_to dashboard_path if Current.user
  end

  def help; end

  def terms; end

  def privacy; end

  private

  def require_saas_legal!
    not_found unless Screenote::Deployment.current.saas?
  end
end
