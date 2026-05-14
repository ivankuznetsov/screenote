---
status: ready
priority: p2
issue_id: "087"
tags: [code-review, security, oauth]
dependencies: []
---

# No Rate Limiting on DCR Endpoint

## Problem Statement
The Dynamic Client Registration endpoint (`POST /oauth/register`) is completely unauthenticated with no rate limiting, CAPTCHA, or IP-based throttling. An attacker can create unlimited `Doorkeeper::Application` records, exhausting database resources. No length validation on `client_name` either.

## Findings
- `app/controllers/oauth/registrations_controller.rb`: `skip_before_action :require_authentication` + `skip_before_action :verify_authenticity_token`
- No `Rack::Attack` throttle configured for this endpoint
- Agents: security-sentinel (C2), architecture-strategist, agent-native-reviewer

## Proposed Solutions

### Option A: Rails built-in rate limiting (Recommended)
Use Rails 8's built-in `rate_limit` in the controller:
```ruby
class Oauth::RegistrationsController < ApplicationController
  rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip }, with: -> { head :too_many_requests }
end
```
Also add `client_name` length validation (max 255 chars) and limit `redirect_uris` to max 10 entries.
- Pros: Rails built-in, no extra gems, simple
- Cons: None
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: `app/controllers/oauth/registrations_controller.rb`

## Acceptance Criteria
- [ ] DCR endpoint limited to 10 registrations/hour/IP
- [ ] `client_name` limited to 255 characters
- [ ] `redirect_uris` limited to max 10 entries
- [ ] Proper 429 response with Retry-After header

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Use Rails built-in rate_limit instead of Rack::Attack
