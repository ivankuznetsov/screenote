# frozen_string_literal: true

class AnnotationCommentsController < ApplicationController
  include ImageAttachmentSubmission

  before_action :set_screenshot
  before_action :set_annotation

  def create
    return respond_invalid_reopen if reopen_action? && !@annotation.resolved?

    batch = submission_batch(@project)
    ImageAttachments::ClaimBatch.call(batch: batch, user: Current.user, project: @project) do
      reopen_action? ? reopen_annotation! : add_comment!
    end

    respond_created
  rescue ActiveRecord::RecordInvalid => error
    respond_invalid(error.record)
  end

  private

  def reopen_annotation!
    @annotation.reopen!(user: Current.user, body: comment_body)
  end

  def add_comment!
    @annotation.annotation_comments.create!(user: Current.user, body: comment_body, action: :comment)
  end

  def respond_created
    respond_to do |format|
      format.json do
        render json: {
          status: "created",
          annotation_id: @annotation.id,
          redirect_url: page_workspace_path_for(@screenshot, viewport: @annotation.viewport)
        }, status: :created
      end
      format.html do
        redirect_to page_workspace_path_for(@screenshot, viewport: @annotation.viewport),
          notice: reopen_action? ? "Annotation unresolved." : "Comment added."
      end
    end
  end

  def respond_invalid(record)
    respond_to do |format|
      format.json { render_submission_error(record.errors.full_messages, batch: submission_batch_for_state) }
      format.html do
        redirect_to page_workspace_path_for(@screenshot, viewport: @annotation.viewport),
          alert: "Could not save comment."
      end
    end
  end

  # Unresolving an annotation that is already open is an ordinary conflict, not
  # a missing record: the composer stays mounted and keeps the person's text.
  def respond_invalid_reopen
    respond_to do |format|
      format.json do
        render_submission_error([ "This annotation is not resolved" ],
          code: "annotation_not_resolved", batch: submission_batch_for_state)
      end
      # The non-JavaScript fallback has no composer to preserve, so it keeps
      # answering an impossible transition as a missing resource.
      format.html { raise ActiveRecord::RecordNotFound, "Annotation is not resolved" }
    end
  end

  def attachment_error_redirect_path
    page_workspace_path_for(@screenshot, viewport: @annotation.viewport)
  end

  def set_screenshot
    @screenshot = Screenshot.find(params[:screenshot_id])
    @project = Current.user.projects.find(@screenshot.page.project_id)
  end

  def set_annotation
    @annotation = @screenshot.annotations.find(params[:annotation_id])
  end

  def comment_body
    params.require(:annotation_comment).permit(:body, :reopen)[:body]
  end

  def reopen_action?
    params.dig(:annotation_comment, :reopen) == "1"
  end
end
