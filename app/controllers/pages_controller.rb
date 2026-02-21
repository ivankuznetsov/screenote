# frozen_string_literal: true

class PagesController < ApplicationController
  before_action :set_project, only: %i[new create]
  before_action :set_page, only: %i[show edit update destroy]

  def show
    @screenshots = @page.screenshots
      .with_attached_image
      .left_joins(:annotations)
      .select("screenshots.*, COUNT(annotations.id) AS annotations_count_cache, COUNT(CASE WHEN annotations.status = 0 THEN 1 END) AS open_annotations_count_cache")
      .group("screenshots.id")
      .order(created_at: :desc)
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
    @page = Page.find(params[:id])
    @project = Current.user.projects.find(@page.project_id)
  end

  def page_params
    params.require(:page).permit(:name)
  end
end
