---
status: ready
priority: p2
issue_id: "093"
tags: [code-review, mcp-spec, oauth]
dependencies: []
---

# Authorization Server Metadata Missing Recommended Fields

## Problem Statement
The `/.well-known/oauth-authorization-server` response is missing `client_id_metadata_document_supported` which MCP clients need to decide whether to use CIMD or fall back to DCR. Also missing `response_modes_supported`.

## Findings
- `app/controllers/oauth_metadata_controller.rb` lines 16-29
- MCP spec: Authorization servers advertise CIMD support with `client_id_metadata_document_supported`
- Agent: agent-native-reviewer (Warning #5)

## Proposed Solutions

### Option A: Add missing fields (Recommended)
```ruby
render json: {
  # ... existing fields ...
  client_id_metadata_document_supported: false,
  response_modes_supported: [ "query" ]
}
```
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: `app/controllers/oauth_metadata_controller.rb`

## Acceptance Criteria
- [ ] `client_id_metadata_document_supported: false` present in response
- [ ] Test updated

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
