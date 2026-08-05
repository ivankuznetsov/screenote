# frozen_string_literal: true

class ApiKeysController < ApplicationController
  include ProjectAuthorization

  before_action :set_project
  before_action :require_owner!
  before_action :set_api_key, only: :destroy

  def index
    @api_keys = @project.api_keys.order(created_at: :desc)
  end

  def new
    @api_key = @project.api_keys.build(issued_by_user: Current.user)
  end

  def create
    @api_key = @project.api_keys.build(api_key_params.merge(issued_by_user: Current.user))

    case save_api_key_with_current_authority
    when :saved
      flash[:api_key_token] = @api_key.raw_token
      redirect_to project_api_keys_path(@project), notice: "API key created. Copy it now — it won't be shown again."
    when :invalid
      render :new, status: :unprocessable_entity
    when :forbidden
      redirect_to projects_path, alert: "You don't have permission to do that."
    end
  end

  def destroy
    @api_key.revoke!
    redirect_to project_api_keys_path(@project), notice: "API key revoked."
  end

  private

  def set_api_key
    @api_key = @project.api_keys.active.find(params[:id])
  end

  def api_key_params
    params.require(:api_key).permit(:name)
  end

  def save_api_key_with_current_authority
    Oauth::PrincipalBinding.with_locked_project(user: Current.user, project_id: @project.id) do |valid, membership|
      next :forbidden unless valid && membership.owner?

      @api_key.save ? :saved : :invalid
    end
  end
end
