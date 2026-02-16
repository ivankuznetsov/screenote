# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  delegate :user, :user=, :session, :session=, to: "RailsSimpleAuth::Current"

  attribute :mcp_project, :mcp_api_key, :mcp_oauth_token
end
