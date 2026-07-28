# frozen_string_literal: true

class AnnotationsController < ApplicationController
  before_action :set_screenshot
  before_action :set_annotation, only: %i[update destroy]

  def create
    return redirect_invalid_viewport unless submitted_viewport_valid?

    @annotation = @screenshot.annotations.build(annotation_params)
    @annotation.user = Current.user

    if @annotation.save
      redirect_to page_workspace_path_for(@screenshot, viewport: @annotation.viewport), notice: "Annotation added."
    else
      redirect_to page_workspace_path_for(@screenshot, viewport: @annotation.viewport),
        alert: "Could not save annotation."
    end
  end

  def update
    original_viewport = @annotation.viewport
    return redirect_invalid_viewport(viewport: original_viewport) unless submitted_viewport_valid?

    if resolving?
      @annotation.resolve!(user: Current.user, body: "Marked as resolved")
      redirect_to page_workspace_path_for(@screenshot, viewport: original_viewport), notice: "Annotation updated."
    else
      @annotation.assign_attributes(annotation_params)

      if @annotation.save
        redirect_to page_workspace_path_for(@screenshot, viewport: @annotation.viewport), notice: "Annotation updated."
      else
        redirect_to page_workspace_path_for(@screenshot, viewport: original_viewport),
          alert: "Could not update annotation."
      end
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to page_workspace_path_for(@screenshot, viewport: original_viewport),
      alert: "Could not update annotation."
  end

  def destroy
    viewport = @annotation.viewport
    @annotation.destroy
    redirect_to page_workspace_path_for(@screenshot, viewport: viewport), notice: "Annotation deleted."
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
    params.require(:annotation).permit(:x_percent, :y_percent, :width_percent, :height_percent, :comment, :viewport)
  end

  def resolving?
    params.dig(:annotation, :status)&.to_s == "resolved" && @annotation.open?
  end

  def submitted_viewport_valid?
    viewport = params.dig(:annotation, :viewport)
    viewport.blank? || Annotation.viewports.key?(viewport.to_s)
  end

  def redirect_invalid_viewport(viewport: nil)
    redirect_to page_workspace_path_for(@screenshot, viewport: viewport), alert: "Could not save annotation."
  end
end
