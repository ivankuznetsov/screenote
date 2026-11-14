# frozen_string_literal: true

# Invitation acceptance outcomes after which the link can never succeed, so
# its authentication-link context is discarded from the session.
module InvitationLinkStatus
  extend ActiveSupport::Concern

  TERMINAL_INVITATION_STATUSES = %i[
    invalid expired cancelled already_used superseded issuer_revoked
  ].freeze

  private

  def terminal_invitation_status?(status)
    TERMINAL_INVITATION_STATUSES.include?(status)
  end
end
