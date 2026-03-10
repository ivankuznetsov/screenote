# frozen_string_literal: true

class SendDigestNotificationsJob < ApplicationJob
  queue_as :default

  def perform
    resolutions = unnotified_resolutions.to_a
    return if resolutions.empty?

    resolutions
      .group_by { |c| c.annotation.user }
      .each do |author, comments|
        next if author.nil? || author.email.blank?

        non_self = comments.reject { |c| c.user.present? && c.user == author }
        next if non_self.empty?

        NotificationMailer.resolution_digest(author, non_self).deliver_now
      end

    mark_all_notified(resolutions)
  end

  private

  def unnotified_resolutions
    AnnotationComment
      .where(action: :resolved, notified_at: nil)
      .joins(annotation: { screenshot: { page: :project } })
      .includes(:user, annotation: [ :user, :annotation_comments, { screenshot: { page: :project } } ])
  end

  def mark_all_notified(comments)
    AnnotationComment.where(id: comments.map(&:id)).update_all(notified_at: Time.current)
  end
end
