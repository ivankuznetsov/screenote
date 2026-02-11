# frozen_string_literal: true

class User < ApplicationRecord
  include RailsSimpleAuth::Models::Concerns::Authenticatable
  include RailsSimpleAuth::Models::Concerns::Confirmable
  include RailsSimpleAuth::Models::Concerns::MagicLinkable
  include RailsSimpleAuth::Models::Concerns::OAuthConnectable

  has_many :sessions, dependent: :destroy
  has_many :projects, dependent: :destroy

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
