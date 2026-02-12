# frozen_string_literal: true

class ProjectMembership < ApplicationRecord
  belongs_to :project
  belongs_to :user

  enum :role, { member: 0, owner: 1 }

  validates :user_id, uniqueness: { scope: :project_id, message: "is already a member" }
  validates :role, presence: true
end
