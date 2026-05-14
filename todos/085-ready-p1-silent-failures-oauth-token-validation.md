---
status: ready
priority: p1
issue_id: "085"
tags: [code-review, observability, oauth]
dependencies: []
---

# Silent Failures in validate_oauth_token — No Logging

## Problem Statement
`validate_oauth_token` has four distinct failure modes that are all collapsed into an identical silent `return false` with zero logging or Honeybadger notification: token not found, token expired, token revoked, project deleted. This makes production debugging of OAuth failures nearly impossible. The project not found case is especially concerning — if a project is deleted, all agents with tokens for that project silently stop working with no trace.

## Findings
- `config/initializers/fast_mcp.rb` lines 61-72: Four `return false` paths with no logging
- `config/initializers/fast_mcp.rb` lines 49-58: `validate_api_key` has the same pattern
- Agent: silent-failure-hunter (CRITICAL #1, #3)

## Proposed Solutions

### Option A: Differentiated logging per failure path (Recommended)
```ruby
def validate_oauth_token(token)
  access_token = Doorkeeper::AccessToken.by_token(token)
  unless access_token
    Rails.logger.info("OAuth: token not found")
    return false
  end
  if access_token.revoked?
    Rails.logger.info("OAuth: token revoked (id=#{access_token.id})")
    return false
  end
  if access_token.expired?
    Rails.logger.info("OAuth: token expired (id=#{access_token.id})")
    return false
  end
  project = Project.find_by(id: access_token.project_id)
  unless project
    Rails.logger.error("OAuth: project not found (token_id=#{access_token.id}, project_id=#{access_token.project_id})")
    Honeybadger.notify("OAuth token references deleted project", context: { token_id: access_token.id, project_id: access_token.project_id })
    return false
  end
  Current.mcp_project = project
  Current.mcp_oauth_token = access_token
  true
end
```
Apply same pattern to `validate_api_key`.
- Pros: Makes production debugging possible, alerts on data integrity issues
- Cons: Slightly more verbose
- Effort: Small
- Risk: Low

## Recommended Action
Option A

## Technical Details
- Affected files: `config/initializers/fast_mcp.rb`

## Acceptance Criteria
- [ ] Each failure path in `validate_oauth_token` logs at appropriate level
- [ ] Project-not-found case notifies Honeybadger
- [ ] Same treatment applied to `validate_api_key`
- [ ] API key nil-project case also handled

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready

## Resources
- Honeybadger Ruby: https://docs.honeybadger.io/lib/ruby/
