# frozen_string_literal: true

class PagesController < ApplicationController
  before_action :set_project, only: %i[new create]
  before_action :set_page, only: %i[show edit update destroy]

  def show
    @projects = Current.user.projects.select(:id, :name).order(:name).to_a
    @screenshots = @page.screenshots.recent_first.includes(:screenshot_images).to_a
    @screenshot = selected_screenshot
    load_workspace if @screenshot
  end

  def new
    @page = @project.pages.build
  end

  def create
    @page = @project.pages.build(page_params)

    if @page.save
      redirect_to page_path(@page), notice: "Page created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @page.update(page_params)
      redirect_to page_path(@page), notice: "Page updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    project = @project
    @page.destroy
    redirect_to project_path(project), notice: "Page deleted."
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id])
  end

  def set_page
    @page = Page.joins(project: :project_memberships)
      .where(project_memberships: { user_id: Current.user.id })
      .find(params[:id])
    @project = @page.project
  end

  def page_params
    params.require(:page).permit(:name)
  end

  def selected_screenshot
    selected = @screenshots.find { |screenshot| screenshot.id.to_s == params[:version_id].to_s }
    selected || @screenshots.first
  end

  def load_workspace
    @active_viewport = page_workspace_viewport_for(@screenshot, params[:viewport])
    @screenshot_image = @screenshot.image_for(@active_viewport) if @active_viewport
    @annotations = @screenshot.annotations
      .includes(:user, annotation_comments: [ :user, :api_key ])
      .order(:created_at)
    @annotations = @annotations.where(status: params[:status]) if Annotation.statuses.key?(params[:status])
    @annotations = @annotations.where(viewport: @active_viewport) if @active_viewport
  end
end
