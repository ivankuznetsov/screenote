# frozen_string_literal: true

class AnnotationCommentsController < ApplicationController
  before_action :set_screenshot
  before_action :set_annotation

  def create
    viewport = @annotation.viewport

    if reopen_action?
      @annotation.reopen!(user: Current.user, body: comment_body)
      redirect_to page_workspace_path_for(@screenshot, viewport: viewport), notice: "Annotation unresolved."
    else
      @annotation.annotation_comments.create!(
        user: Current.user,
        body: comment_body,
        action: :comment
      )
      redirect_to page_workspace_path_for(@screenshot, viewport: viewport), notice: "Comment added."
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to page_workspace_path_for(@screenshot, viewport: viewport), alert: "Could not save comment."
  end

  private

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
