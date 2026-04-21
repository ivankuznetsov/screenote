---
title: Current
type: model
source: app/models/current.rb
created: 2026-04-10
updated: 2026-04-10
tags: [model, current-attributes, auth, context]
---

# Current

TLDR: Thread-local request context using ActiveSupport::CurrentAttributes. Delegates user/session to RailsSimpleAuth::Current and adds MCP-specific attributes.

Source: `app/models/current.rb`

## Delegates

- `user`, `user=` -- from `RailsSimpleAuth::Current`
- `session`, `session=` -- from `RailsSimpleAuth::Current`

## Attributes

- `mcp_user` -- The authenticated user for MCP requests
- `mcp_project` -- The project scoped by the MCP OAuth token
- `mcp_api_key` -- The API key associated with the MCP session
- `mcp_oauth_token` -- The Doorkeeper OAuth token for the current MCP request

## Notes

- `Current.user` is the primary way to access the authenticated user throughout the app.
- MCP attributes are set separately from web session attributes because MCP uses OAuth 2.1 auth, not cookie sessions.

See also: [[user]], [[architecture]]
