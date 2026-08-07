---
title: Current
type: model
source: app/models/current.rb
created: 2026-04-10
updated: 2026-08-05
tags: [model, current-attributes, auth, context]
---

# Current

TLDR: Thread-local request context using ActiveSupport::CurrentAttributes. Browser user/session state remains delegated to RailsSimpleAuth, while bearer-authenticated requests carry one immutable principal.

Source: `app/models/current.rb`

## Delegates

- `user`, `user=` -- from `RailsSimpleAuth::Current`
- `session`, `session=` -- from `RailsSimpleAuth::Current`

## Attribute

- `authenticated_principal` -- The immutable user- or project-principal resolved for REST/MCP OAuth tokens and project API keys. It contains exact scopes and the credential's authoritative project/actor provenance; the same value object can represent a browser user for shared domain operations.

## Notes

- `Current.user` is the primary way to access the authenticated user throughout the app.
- MCP transport identity is separate from web session state because MCP uses bearer authentication, not cookie sessions.
- MCP transport resets `authenticated_principal` at both request entry and exit. Tools may resolve a project from the principal but cannot mutate request identity or treat an API-key issuer as the acting user.

See also: [[user]], [[architecture]], [[mcp-tools]]
