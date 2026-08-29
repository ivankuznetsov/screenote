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
    annotation = resolution_comment.annotation
    reply = annotation.annotation_comments
      .select { |c| c.comment? && c.created_at <= resolution_comment.created_at }
      .max_by(&:created_at)

    {
      annotation_text: annotation.comment,
      annotation_attachments: attachment_metadata(annotation.image_attachments),
      reply_text: reply&.body,
      reply_attachments: attachment_metadata(reply&.image_attachments),
      resolver: resolution_comment.user&.email || "API",
      url: annotation_workspace_url(annotation)
    }
  end

  # Digest mail carries descriptions and counts only. An attachment URL would
  # outlive the five-minute window it is minted for and would not be authorized
  # from a mail client anyway, so the call to action is a deep link into the
  # workspace instead.
  def attachment_metadata(attachments)
    Array(attachments&.to_a).map do |attachment|
      {
        alt_text: attachment.display_alt_text,
        media_type: attachment.media_type,
        width: attachment.width,
        height: attachment.height,
        size: attachment.byte_size
      }
    end
  end

  def annotation_workspace_url(annotation)
    screenshot = annotation.screenshot
    options = { version_id: screenshot.id }
    options[:viewport] = annotation.viewport if screenshot.available_viewports.include?(annotation.viewport.to_s)

    "#{routes.page_url(screenshot.page_id, **options, **Screenote::Deployment.current.url_options)}" \
      "##{ActionView::RecordIdentifier.dom_id(annotation)}"
  end

  def routes
    Rails.application.routes.url_helpers
  end
end
