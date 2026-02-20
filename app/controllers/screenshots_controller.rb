# frozen_string_literal: true

class ScreenshotsController < ApplicationController
  before_action :set_page, only: %i[new create]
  before_action :set_screenshot, only: %i[show edit update destroy]

  def show
    @annotations = @screenshot.annotations.includes(:user).order(:created_at)
    @annotations = @annotations.where(status: params[:status]) if params[:status].in?(%w[open resolved])
  end

  def new
    @screenshot = @page.screenshots.build
  end

  def create
    @screenshot = @page.screenshots.build(screenshot_params)

    if @screenshot.save
      redirect_to screenshot_path(@screenshot), notice: "Screenshot uploaded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @screenshot.update(screenshot_params)
      redirect_to screenshot_path(@screenshot), notice: "Screenshot updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    page = @page
    @screenshot.destroy
    redirect_to page_path(page), notice: "Screenshot deleted."
  end

  private

  def set_page
    @page = Page.find(params[:page_id])
    @project = Current.user.projects.find(@page.project_id)
  end

  def set_screenshot
    @screenshot = Screenshot.find(params[:id])
    @page = @screenshot.page
    @project = Current.user.projects.find(@page.project_id)
  end

  def screenshot_params
    params.require(:screenshot).permit(:title, :image)
  end
end
