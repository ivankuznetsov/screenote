# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def resolution_digest(recipient, comments)
    @recipient = recipient
    @grouped = prepare_grouped_comments(comments)

    mail(
      to: recipient.email,
      subject: subject_line(comments)
    )
  end

  private

  def subject_line(comments)
    count = comments.size
    project_names = comments.filter_map { |c| c.annotation&.screenshot&.page&.project&.name }.uniq
    project_label = project_names.size == 1 ? project_names.first : "#{project_names.size} projects"
    "[Screenote] #{count} annotation#{'s' if count > 1} resolved in #{project_label}"
  end

  def prepare_grouped_comments(comments)
    comments.group_by { |c| c.annotation.screenshot }.map do |screenshot, screenshot_comments|
      {
        page_name: screenshot.page.name,
        screenshot_title: screenshot.title,
        items: screenshot_comments.map { |c| build_item(c) }
      }
    end
  end

  def build_item(resolution_comment)
    reply = resolution_comment.annotation.annotation_comments
      .select { |c| c.comment? && c.created_at <= resolution_comment.created_at }
      .max_by(&:created_at)

    {
      annotation_text: resolution_comment.annotation.comment,
      reply_text: reply&.body,
      resolver: resolution_comment.user&.email || "API"
    }
  end
end
