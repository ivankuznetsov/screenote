---
status: ready
priority: p1
issue_id: "083"
tags: [code-review, oauth, mcp-spec]
dependencies: []
---

# WWW-Authenticate resource_metadata Uses Relative URL

## Problem Statement
The `WWW-Authenticate` header in the 401 response uses a relative path `/.well-known/oauth-protected-resource` instead of an absolute URL. RFC 9728 Section 5.1 mandates an absolute URL. MCP clients that strictly follow the spec will fail to resolve the metadata URL, breaking the entire OAuth discovery flow.

## Findings
- `config/initializers/fast_mcp.rb` line 91: `"Bearer resource_metadata=\"/.well-known/oauth-protected-resource\""`
- RFC 9728 example: `WWW-Authenticate: Bearer resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource"`
- Agent: agent-native-reviewer (P0)

## Proposed Solutions

### Option A: Build absolute URL from Rack request (Recommended)
```ruby
def unauthorized_response(request)
  rack_request = request.is_a?(Hash) ? Rack::Request.new(request) : request
  base_url = "#{rack_request.scheme}://#{rack_request.host_with_port}"
  # ...
  "WWW-Authenticate" => "Bearer resource_metadata=\"#{base_url}/.well-known/oauth-protected-resource\""
end
```
- Pros: Dynamic, works in all environments
- Cons: Slightly more complex
- Effort: Small
- Risk: Low

## Recommended Action
Option A

## Technical Details
- Affected files: `config/initializers/fast_mcp.rb`

## Acceptance Criteria
- [ ] WWW-Authenticate header contains an absolute URL
- [ ] Works correctly in both development (localhost:3005) and production
- [ ] Test verifies the header contains a full URL

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready

## Resources
- RFC 9728: https://www.rfc-editor.org/rfc/rfc9728
- MCP Auth Spec: https://modelcontextprotocol.io/specification/draft/basic/authorization
