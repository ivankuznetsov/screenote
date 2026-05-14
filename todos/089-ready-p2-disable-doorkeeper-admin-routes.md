---
status: ready
priority: p2
issue_id: "089"
tags: [code-review, security, oauth]
dependencies: []
---

# Doorkeeper Admin Routes Exposed

## Problem Statement
`use_doorkeeper` mounts full CRUD routes for `/oauth/applications`, `/oauth/authorized_applications`, and `/oauth/token/info`. These are unnecessary (Screenote uses DCR for client registration) and expose attack surface. The token info endpoint also leaks token metadata.

## Findings
- `config/routes.rb` lines 4-6: `use_doorkeeper` with no `skip_controllers`
- Routes exposed: GET/POST/PATCH/DELETE `/oauth/applications`, GET/DELETE `/oauth/authorized_applications`, GET `/oauth/token/info`
- Agents: security-sentinel (M5, M7), architecture-strategist

## Proposed Solutions

### Option A: skip_controllers (Recommended)
```ruby
use_doorkeeper do
  controllers authorizations: "oauth/authorizations"
  skip_controllers :applications, :authorized_applications, :token_info
end
```
- Pros: Simple, removes unnecessary routes
- Cons: None
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: `config/routes.rb`

## Acceptance Criteria
- [ ] `/oauth/applications` routes return 404
- [ ] `/oauth/token/info` returns 404
- [ ] Authorization and token endpoints still work

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
