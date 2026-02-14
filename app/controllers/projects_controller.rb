# frozen_string_literal: true

class ProjectsController < ApplicationController
  include ProjectAuthorization

  before_action :set_project, only: %i[show edit update destroy]
  before_action :require_owner!, only: %i[edit update destroy]

  def index
    @memberships_by_project = Current.user.project_memberships.includes(:project).index_by(&:project_id)
    @projects = Current.user.projects.order(updated_at: :desc)
  end

  def show
    @is_owner = @project.owner?(Current.user)
    @screenshots = @project.screenshots
      .with_attached_image
      .left_joins(:annotations)
      .select("screenshots.*, COUNT(annotations.id) AS annotations_count_cache, COUNT(CASE WHEN annotations.status = 0 THEN 1 END) AS open_annotations_count_cache")
      .group("screenshots.id")
      .order(created_at: :desc)
  end

  def new
    unless Current.user.can_create_project?
      redirect_to subscription_path, alert: "You've reached the free plan limit of 1 project. Upgrade to Pro for unlimited projects."
      return
    end

    @project = Current.user.owned_projects.build
  end

  def create
    unless Current.user.can_create_project?
      redirect_to subscription_path, alert: "You've reached the free plan limit of 1 project. Upgrade to Pro for unlimited projects."
      return
    end

    @project = Current.user.owned_projects.build(project_params)

    if @project.save
      redirect_to @project, notice: "Project created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: "Project deleted."
  end

  private

  def project_params
    params.require(:project).permit(:name, :description)
  end
end
