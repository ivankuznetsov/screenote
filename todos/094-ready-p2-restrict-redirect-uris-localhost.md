---
status: ready
priority: p2
issue_id: "094"
tags: [code-review, security, oauth]
dependencies: []
---

# DCR Allows Arbitrary Redirect URI Domains

## Problem Statement
The DCR endpoint allows any redirect URI. In production, a malicious registration could use `https://evil.example.com/callback` and social-engineer a user into sending the authorization code to an attacker's server. For MCP clients, redirect URIs should only be localhost.

## Findings
- `app/controllers/oauth/registrations_controller.rb`: No redirect URI domain validation
- MCP clients use localhost redirects exclusively
- Agent: security-sentinel (M6)

## Proposed Solutions

### Option A: Restrict to localhost (Recommended)
```ruby
redirect_uris.each do |uri|
  parsed = URI.parse(uri)
  unless parsed.host.in?(%w[localhost 127.0.0.1 ::1])
    return render json: { error: "invalid_client_metadata",
      error_description: "Only localhost redirect URIs are allowed" }, status: :bad_request
  end
end
```
- Effort: Small
- Risk: Low (may need adjustment if non-localhost clients are needed later)

## Technical Details
- Affected files: `app/controllers/oauth/registrations_controller.rb`

## Acceptance Criteria
- [ ] Non-localhost redirect URIs rejected
- [ ] Localhost variants (127.0.0.1, ::1) accepted
- [ ] Any port number accepted on localhost

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
