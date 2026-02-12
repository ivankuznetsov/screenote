# frozen_string_literal: true

class Project < ApplicationRecord
  belongs_to :creator, class_name: "User", foreign_key: :user_id
  has_many :project_memberships, dependent: :destroy
  has_many :members, through: :project_memberships, source: :user
  has_many :project_invitations, dependent: :destroy
  has_many :screenshots, dependent: :destroy
  has_many :api_keys, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }

  after_create :create_owner_membership

  def member?(check_user)
    project_memberships.exists?(user_id: check_user.id)
  end

  def role_for(check_user)
    project_memberships.find_by(user_id: check_user.id)&.role&.to_sym
  end

  def owner?(check_user)
    project_memberships.exists?(user_id: check_user.id, role: :owner)
  end

  private

  def create_owner_membership
    project_memberships.create!(user: creator, role: :owner)
  end
end
