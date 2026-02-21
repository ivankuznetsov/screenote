# frozen_string_literal: true

class AnnotationsController < ApplicationController
  before_action :set_screenshot
  before_action :set_annotation, only: %i[update destroy]

  def create
    @annotation = @screenshot.annotations.build(annotation_params)
    @annotation.user = Current.user

    if @annotation.save
      redirect_to screenshot_path(@screenshot), notice: "Annotation added."
    else
      redirect_to screenshot_path(@screenshot), alert: "Could not save annotation."
    end
  end

  def update
    if resolving?
      @annotation.resolve!(user: Current.user, body: "Marked as resolved")
      redirect_to screenshot_path(@screenshot), notice: "Annotation updated."
    else
      @annotation.assign_attributes(annotation_params)

      if @annotation.save
        redirect_to screenshot_path(@screenshot), notice: "Annotation updated."
      else
        redirect_to screenshot_path(@screenshot), alert: "Could not update annotation."
      end
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to screenshot_path(@screenshot), alert: "Could not update annotation."
  end

  def destroy
    @annotation.destroy
    redirect_to screenshot_path(@screenshot), notice: "Annotation deleted."
  end

  private

  def set_screenshot
    @screenshot = Screenshot.find(params[:screenshot_id])
    @project = Current.user.projects.find(@screenshot.page.project_id)
  end

  def set_annotation
    @annotation = @screenshot.annotations.find(params[:id])
  end

  def annotation_params
    params.require(:annotation).permit(:x_percent, :y_percent, :width_percent, :height_percent, :comment)
  end

  def resolving?
    params.dig(:annotation, :status)&.to_s == "resolved" && @annotation.open?
  end
end
