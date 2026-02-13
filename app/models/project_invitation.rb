# frozen_string_literal: true

class ProjectInvitation < ApplicationRecord
  belongs_to :project
  belongs_to :inviter, class_name: "User"

  enum :status, { pending: 0, accepted: 1 }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: :project_id, conditions: -> { where(status: :pending) }, message: "has already been invited" }
  validate :not_already_member

  normalizes :email, with: ->(email) { email.strip.downcase }

  # Token invalidates when status changes from "pending" to "accepted"
  generates_token_for :accept, expires_in: 7.days do
    status
  end

  def accept!(user)
    with_lock do
      return if accepted?

      update!(status: :accepted)
      project.project_memberships.find_or_create_by!(user: user) do |m|
        m.role = :member
      end
    end
  end

  private

  def not_already_member
    return unless project

    existing_user = User.find_by(email: email)
    return unless existing_user

    errors.add(:email, "is already a member of this project") if project.member?(existing_user)
  end
end
