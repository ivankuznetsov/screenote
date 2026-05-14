---
status: ready
priority: p2
issue_id: "092"
tags: [code-review, mcp-spec, oauth]
dependencies: []
---

# Protected Resource Metadata Missing scopes_supported

## Problem Statement
The `/.well-known/oauth-protected-resource` response is missing the `scopes_supported` field. MCP clients need this to determine what scopes to request when the `WWW-Authenticate` header does not include a `scope` parameter. The `WWW-Authenticate` header is also missing a `scope` parameter.

## Findings
- `app/controllers/oauth_metadata_controller.rb` lines 7-13: Response lacks `scopes_supported`
- `config/initializers/fast_mcp.rb` line 91: `WWW-Authenticate` header lacks `scope` parameter
- RFC 9728 Section 4: `scopes_supported` is recommended
- RFC 6750 Section 3: `scope` in WWW-Authenticate is recommended
- Agent: agent-native-reviewer (Warning #3, #4)

## Proposed Solutions

### Option A: Add both fields (Recommended)
Protected Resource Metadata:
```ruby
render json: {
  resource: mcp_resource_url,
  authorization_servers: [ root_url.chomp("/") ],
  bearer_methods_supported: [ "header" ],
  scopes_supported: [ "mcp_read", "mcp_write" ]
}
```
WWW-Authenticate header:
```ruby
"Bearer resource_metadata=\"#{base_url}/.well-known/oauth-protected-resource\", scope=\"mcp_read mcp_write\""
```
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: `app/controllers/oauth_metadata_controller.rb`, `config/initializers/fast_mcp.rb`

## Acceptance Criteria
- [ ] Protected Resource Metadata includes `scopes_supported`
- [ ] WWW-Authenticate header includes `scope` parameter
- [ ] Tests updated

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
