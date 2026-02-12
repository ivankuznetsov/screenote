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
    @api_key = @project.api_keys.build
  end

  def create
    @api_key = @project.api_keys.build(api_key_params)

    if @api_key.save
      flash[:api_key_token] = @api_key.raw_token
      redirect_to project_api_keys_path(@project), notice: "API key created. Copy it now — it won't be shown again."
    else
      render :new, status: :unprocessable_entity
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
end
