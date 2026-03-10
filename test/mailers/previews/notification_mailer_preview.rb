# frozen_string_literal: true

# Preview all emails at http://localhost:3005/rails/mailers/notification_mailer
class NotificationMailerPreview < ActionMailer::Preview
  # Single annotation resolved
  def resolution_digest_single
    comment = resolved_comment
    NotificationMailer.resolution_digest(comment.annotation.user, [ comment ])
  end

  # Multiple annotations resolved across different screenshots
  def resolution_digest_multiple
    comments = AnnotationComment.where(action: :resolved).includes(annotation: { screenshot: { page: :project } }).limit(5).to_a

    if comments.size < 2
      comments = [ resolved_comment, resolved_comment_with_reply ]
    end

    recipient = comments.first.annotation.user
    NotificationMailer.resolution_digest(recipient, comments)
  end

  # Resolution with a reply comment before it
  def resolution_digest_with_reply
    comment = resolved_comment_with_reply
    NotificationMailer.resolution_digest(comment.annotation.user, [ comment ])
  end

  private

  def resolved_comment
    AnnotationComment.find_by(action: :resolved) || build_preview_resolution
  end

  def resolved_comment_with_reply
    resolution = resolved_comment

    unless resolution.annotation.annotation_comments.where(action: :comment).exists?
      resolution.annotation.annotation_comments.create!(
        user: resolver_user,
        body: "Fixed: increased button font size to 16px.\nChanged: app/assets/stylesheets/buttons.css:42 — updated font-size from 12px to 16px",
        action: :comment,
        created_at: resolution.created_at - 1.minute
      )
    end

    resolution
  end

  def build_preview_resolution
    annotation = Annotation.first || build_preview_annotation
    annotation.annotation_comments.find_by(action: :resolved) ||
      annotation.annotation_comments.create!(
        user: resolver_user,
        body: "Fixed the issue",
        action: :resolved
      )
  end

  def build_preview_annotation
    screenshot = Screenshot.first
    user = User.first
    screenshot.annotations.create!(
      user: user,
      x_percent: 50.0,
      y_percent: 30.0,
      comment: "Button text is too small on mobile",
      status: :open
    )
  end

  def resolver_user
    User.where.not(id: User.first&.id).first || User.first
  end
end
