# frozen_string_literal: true

class ScreenshotsController < ApplicationController
  before_action :set_project
  before_action :set_screenshot, only: %i[show edit update destroy]

  def index
    @screenshots = @project.screenshots
      .with_attached_image
      .left_joins(:annotations)
      .select("screenshots.*, COUNT(annotations.id) AS annotations_count_cache, COUNT(CASE WHEN annotations.status = 0 THEN 1 END) AS open_annotations_count_cache")
      .group("screenshots.id")
      .order(created_at: :desc)
  end

  def show
    @annotations = @screenshot.annotations.includes(:user).order(:created_at)
    @annotations = @annotations.where(status: params[:status]) if params[:status].in?(%w[open resolved])
  end

  def new
    @screenshot = @project.screenshots.build
  end

  def create
    @screenshot = @project.screenshots.build(screenshot_params)

    if @screenshot.save
      redirect_to project_screenshot_path(@project, @screenshot), notice: "Screenshot uploaded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @screenshot.update(screenshot_params)
      redirect_to project_screenshot_path(@project, @screenshot), notice: "Screenshot updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @screenshot.destroy
    redirect_to project_screenshots_path(@project), notice: "Screenshot deleted."
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id])
  end

  def set_screenshot
    @screenshot = @project.screenshots.find(params[:id])
  end

  def screenshot_params
    params.require(:screenshot).permit(:title, :image)
  end
end
