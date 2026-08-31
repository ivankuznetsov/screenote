# frozen_string_literal: true

class AnnotationsController < ApplicationController
  include ImageAttachmentSubmission

  before_action :set_screenshot
  before_action :set_annotation, only: %i[update destroy]

  def create
    return respond_invalid_viewport unless submitted_viewport_valid?

    batch = submission_batch(@project)
    result = ImageAttachments::ClaimBatch.call(batch: batch, user: Current.user, project: @project,
      parent_type: Annotation) do
      build_annotation!
    end

    respond_created(result.parent)
  rescue ActiveRecord::RecordInvalid => error
    respond_invalid(error.record)
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

  def build_annotation!
    annotation = @screenshot.annotations.build(annotation_params)
    annotation.user = Current.user
    annotation.save!
    annotation
  end

  def respond_created(annotation)
    respond_to do |format|
      format.json do
        render json: {
          status: "created",
          annotation_id: annotation.id,
          redirect_url: page_workspace_path_for(@screenshot, viewport: annotation.viewport)
        }, status: :created
      end
      format.html do
        redirect_to page_workspace_path_for(@screenshot, viewport: annotation.viewport), notice: "Annotation added."
      end
    end
  end

  def respond_invalid(record)
    respond_to do |format|
      format.json { render_submission_error(record.errors.full_messages, batch: submission_batch_for_state) }
      format.html do
        redirect_to page_workspace_path_for(@screenshot, viewport: record.viewport),
          alert: "Could not save annotation."
      end
    end
  end

  def respond_invalid_viewport
    respond_to do |format|
      format.json do
        render_submission_error([ "Viewport is not available for this screenshot" ],
          code: "invalid_viewport", batch: submission_batch_for_state)
      end
      format.html { redirect_invalid_viewport }
    end
  end

  def attachment_error_redirect_path
    page_workspace_path_for(@screenshot)
  end

  def set_screenshot
    @screenshot = Screenshot.find(params[:screenshot_id])
    @project = Current.user.projects.find(@screenshot.page.project_id)
  end

  def set_annotation
    @annotation = @screenshot.annotations.find(params[:id])
  end

  # Everything the still-mounted overlay needs to put itself back exactly as the
  # person left it: the message, the selected region, and the viewport it was
  # drawn on.
  def submitted_form_fields
    submitted = params.fetch(:annotation, {})
    {
      body: submitted[:comment].to_s,
      x_percent: submitted[:x_percent],
      y_percent: submitted[:y_percent],
      width_percent: submitted[:width_percent],
      height_percent: submitted[:height_percent],
      viewport: submitted[:viewport].presence
    }
  end

  def annotation_params
    permitted_params = params.require(:annotation).permit(
      :x_percent, :y_percent, :width_percent, :height_percent, :comment, :viewport
    )
    permitted_params.delete(:viewport) if permitted_params[:viewport].blank?
    permitted_params
  end

  def resolving?
    params.dig(:annotation, :status)&.to_s == "resolved" && @annotation.open?
  end

  def submitted_viewport_valid?
    viewport = params.dig(:annotation, :viewport)
    viewport.blank? || @screenshot.available_viewports.include?(viewport.to_s)
  end

  def redirect_invalid_viewport(viewport: nil)
    redirect_to page_workspace_path_for(@screenshot, viewport: viewport), alert: "Could not save annotation."
  end
end
