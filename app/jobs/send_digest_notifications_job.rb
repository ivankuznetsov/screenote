# frozen_string_literal: true

class SendDigestNotificationsJob < ApplicationJob
  queue_as :default

  def perform
    unnotified_resolutions
      .group_by { |c| c.annotation.user }
      .each do |author, comments|
        next if author.nil? || author.email.blank?

        non_self = comments.reject { |c| c.user.present? && c.user == author }
        next if non_self.empty?

        send_digest(author, non_self)
      end
  end

  private

  def unnotified_resolutions
    AnnotationComment
      .where(action: :resolved, notified_at: nil)
      .joins(annotation: { screenshot: { page: :project } })
      .includes(:user, annotation: [ :user, :annotation_comments, { screenshot: { page: :project } } ])
  end

  def send_digest(recipient, comments)
    NotificationMailer.resolution_digest(recipient, comments).deliver_now

    AnnotationComment.where(id: comments.map(&:id)).update_all(notified_at: Time.current)
  end
end
