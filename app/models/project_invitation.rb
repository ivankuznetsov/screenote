# frozen_string_literal: true

class ProjectInvitation < ApplicationRecord
  belongs_to :project
  belongs_to :inviter, class_name: "User"

  enum :status, { pending: 0, accepted: 1 }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: :project_id, message: "has already been invited" }
  validate :not_already_member

  normalizes :email, with: ->(email) { email.strip.downcase }

  # Token invalidates when status changes from "pending" to "accepted"
  generates_token_for :accept, expires_in: 7.days do
    status
  end

  def accept!(user)
    transaction do
      update!(status: :accepted)
      project.project_memberships.create!(user: user, role: :member)
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
