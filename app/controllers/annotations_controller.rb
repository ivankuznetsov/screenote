# frozen_string_literal: true

class AnnotationsController < ApplicationController
  before_action :set_project
  before_action :set_screenshot
  before_action :set_annotation, only: %i[update destroy]

  def create
    @annotation = @screenshot.annotations.build(annotation_params)
    @annotation.user = Current.user

    if @annotation.save
      redirect_to project_screenshot_path(@project, @screenshot), notice: "Annotation added."
    else
      redirect_to project_screenshot_path(@project, @screenshot), alert: "Could not save annotation."
    end
  end

  def update
    if @annotation.update(annotation_params)
      redirect_to project_screenshot_path(@project, @screenshot), notice: "Annotation updated."
    else
      redirect_to project_screenshot_path(@project, @screenshot), alert: "Could not update annotation."
    end
  end

  def destroy
    @annotation.destroy
    redirect_to project_screenshot_path(@project, @screenshot), notice: "Annotation deleted."
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id])
  end

  def set_screenshot
    @screenshot = @project.screenshots.find(params[:screenshot_id])
  end

  def set_annotation
    @annotation = @screenshot.annotations.find(params[:id])
  end

  def annotation_params
    params.require(:annotation).permit(:x_percent, :y_percent, :width_percent, :height_percent, :comment, :status)
  end
end
