# frozen_string_literal: true

module ProjectAuthorization
  extend ActiveSupport::Concern

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id] || params[:id])
  end

  def require_owner!
    return if @project.owner?(Current.user)

    redirect_to projects_path, alert: "You don't have permission to do that."
  end
end
