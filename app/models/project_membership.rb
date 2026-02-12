# frozen_string_literal: true

class ProjectMembership < ApplicationRecord
  belongs_to :project
  belongs_to :user

  enum :role, { member: 0, owner: 1 }

  validates :user_id, uniqueness: { scope: :project_id, message: "is already a member" }
  validates :role, presence: true

  before_destroy :prevent_sole_owner_removal

  private

  def prevent_sole_owner_removal
    return unless owner?
    return if project._destroy_in_progress

    unless project.project_memberships.where(role: :owner).where.not(id: id).exists?
      errors.add(:base, "Cannot remove the only owner of a project")
      throw(:abort)
    end
  end
end
