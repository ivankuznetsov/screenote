# frozen_string_literal: true

class AnnotationCommentsController < ApplicationController
  include ImageAttachmentSubmission

  # Raised by the claim's parent builder so that an already-open annotation is
  # reported as an ordinary 422 conflict while still rolling the claim back.
  class NotResolved < StandardError; end

  before_action :set_screenshot
  before_action :set_annotation

  def create
    batch = submission_batch(@project)
    # The resolved-state guard lives inside the parent builder rather than in
    # front of the claim. A retry of a reopen whose response was lost arrives
    # against an annotation the first attempt already opened, and it has to
    # reach the claimed batch — which answers with the comment that reopen
    # already created — instead of being rejected for the state it caused.
    result = ImageAttachments::ClaimBatch.call(batch: batch, user: Current.user, project: @project,
      parent_type: AnnotationComment, parent_matcher: method(:claimed_comment?)) do
      raise NotResolved if reopen_action? && !@annotation.resolved?

      reopen_action? ? reopen_annotation! : add_comment!
    end

    respond_created(result.parent)
  rescue NotResolved
    respond_invalid_reopen
  rescue ActiveRecord::RecordInvalid => error
    respond_invalid(error.record)
  end

  private

  # One batch belongs to one mounted disclosure. Class alone cannot tell them
  # apart: every reply composer in the project, and the reopen composer on this
  # same thread, all produce an AnnotationComment. A replayed public ID must
  # therefore match this thread and this action or it is not owned here.
  def claimed_comment?(comment)
    comment.annotation_id == @annotation.id &&
      comment.action == (reopen_action? ? "reopened" : "comment")
  end

  def reopen_annotation!
    @annotation.reopen!(user: Current.user, body: comment_body)
  end

  def add_comment!
    @annotation.annotation_comments.create!(user: Current.user, body: comment_body, action: :comment)
  end

  def respond_created(comment)
    respond_to do |format|
      format.json do
        render json: {
          status: "created",
          annotation_id: @annotation.id,
          # The submission contract identifies the parent the claim produced,
          # which for a replayed post is the comment the first attempt created.
          annotation_comment_id: comment.id,
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

  # Everything the still-mounted disclosure needs to put itself back exactly as
  # the person left it.
  def submitted_form_fields
    {
      annotation_id: @annotation.id,
      body: params.dig(:annotation_comment, :body).to_s,
      reopen: reopen_action?
    }
  end

  def reopen_action?
    params.dig(:annotation_comment, :reopen) == "1"
  end
end
