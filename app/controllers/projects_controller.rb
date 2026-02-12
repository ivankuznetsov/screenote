# frozen_string_literal: true

class ProjectsController < ApplicationController
  before_action :set_project, only: %i[show edit update destroy]

  def index
    @projects = Current.user.projects.order(updated_at: :desc)
  end

  def show
    @screenshots = @project.screenshots
      .with_attached_image
      .left_joins(:annotations)
      .select("screenshots.*, COUNT(annotations.id) AS annotations_count_cache, COUNT(CASE WHEN annotations.status = 0 THEN 1 END) AS open_annotations_count_cache")
      .group("screenshots.id")
      .order(created_at: :desc)
  end

  def new
    @project = Current.user.projects.build
  end

  def create
    @project = Current.user.projects.build(project_params)

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

  def set_project
    @project = Current.user.projects.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description)
  end
end
