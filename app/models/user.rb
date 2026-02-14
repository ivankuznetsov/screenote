# frozen_string_literal: true

class User < ApplicationRecord
  include RailsSimpleAuth::Models::Concerns::Authenticatable
  include RailsSimpleAuth::Models::Concerns::Confirmable
  include RailsSimpleAuth::Models::Concerns::MagicLinkable
  include RailsSimpleAuth::Models::Concerns::OAuthConnectable

  has_many :sessions, dependent: :destroy
  has_many :owned_projects, class_name: "Project", foreign_key: :user_id, inverse_of: :creator, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships
  has_many :annotations, dependent: :destroy
  has_one :subscription, dependent: :destroy

  def pro?
    subscription&.active_pro? || false
  end

  def can_create_project?
    pro? || owned_projects.count < Subscription::FREE_PROJECT_LIMIT
  end

  def can_invite_member?(project)
    pro? || project.members.count < Subscription::FREE_MEMBER_LIMIT
  end

  def assign_oauth_attributes(auth_hash)
    self.oauth_provider = auth_hash["provider"]
    self.oauth_uid = auth_hash["uid"]
  end

  class << self
    def find_by_oauth(provider, uid)
      find_by(oauth_provider: provider, oauth_uid: uid)
    end
  end
end
