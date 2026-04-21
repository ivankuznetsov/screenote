# frozen_string_literal: true

class Project < ApplicationRecord
  belongs_to :creator, class_name: "User", foreign_key: :user_id, inverse_of: :owned_projects
  has_many :project_memberships, dependent: :destroy
  has_many :members, through: :project_memberships, source: :user
  has_many :project_invitations, dependent: :destroy
  has_many :pages, dependent: :destroy
  has_many :screenshots, through: :pages
  has_many :api_keys, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }

  before_destroy :flag_destroy_in_progress, prepend: true
  after_create :create_owner_membership

  attr_accessor :_destroy_in_progress

  def member?(check_user)
    project_memberships.exists?(user_id: check_user.id)
  end

  def role_for(check_user)
    project_memberships.find_by(user_id: check_user.id)&.role&.to_sym
  end

  def owner?(check_user)
    project_memberships.exists?(user_id: check_user.id, role: :owner)
  end

  def thumbnail_screenshots(limit = 4)
    pages.lazy.filter_map { |p| p.latest_screenshot if p.latest_screenshot&.primary_image&.image&.attached? }.first(limit)
  end

  private

  def create_owner_membership
    project_memberships.create!(user: creator, role: :owner)
  end

  def flag_destroy_in_progress
    self._destroy_in_progress = true
  end
end
