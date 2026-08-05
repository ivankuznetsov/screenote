# frozen_string_literal: true

module OauthPrincipalRecord
  extend ActiveSupport::Concern

  included do
    attr_readonly :principal_kind, :project_id, :resource_owner_id
    validates :principal_kind, inclusion: { in: %w[user project] }
    validate :oauth_principal_shape
  end

  private

  def oauth_principal_shape
    valid =
      case principal_kind
      when "user"
        project_id.nil?
      when "project"
        project_id.present?
      else
        false
      end

    errors.add(:project_id, "must match the OAuth principal kind") unless valid
  end
end
