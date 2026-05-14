---
status: ready
priority: p2
issue_id: "148"
tags: [code-review, rails, rate-limiting]
dependencies: []
---

# Rate limit missing `with:` handler and `by:` user scoping

## Problem Statement
The `rate_limit` call lacks `with: -> { head :too_many_requests }` (inconsistent with other controllers) and defaults to IP-based limiting instead of per-user. In shared-IP environments (offices, VPNs), one user's autocomplete searches count against all users behind that IP.

## Findings
- **Source**: Silent Failure Hunter
- **Location**: `app/controllers/collaborator_suggestions_controller.rb:9`
- Other controllers (`api/screenshot_uploads_controller.rb`, `oauth/registrations_controller.rb`) both use `with: -> { head :too_many_requests }`

## Proposed Solutions
### Option A: Add `with:` and `by:` parameters (Recommended)
`rate_limit to: 30, within: 1.minute, by: -> { Current.user&.id }, with: -> { head :too_many_requests }`
- **Effort**: Small | **Risk**: None

## Acceptance Criteria
- [ ] Rate limit uses `with: -> { head :too_many_requests }`
- [ ] Rate limit scoped by user ID not IP
