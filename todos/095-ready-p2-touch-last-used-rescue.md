---
status: ready
priority: p2
issue_id: "095"
tags: [code-review, reliability, oauth]
dependencies: ["086"]
---

# validate_api_key: touch_last_used! Can Crash Successful Auth

## Problem Statement
In `validate_api_key`, `api_key.touch_last_used!` performs a DB write after successful authentication. If this write fails (disk full, connection issue), the entire auth request crashes despite the token being valid. A non-critical side effect should not block authentication.

## Findings
- `config/initializers/fast_mcp.rb` line 57: `api_key.touch_last_used!` with no rescue
- Agent: silent-failure-hunter (HIGH #3)

## Proposed Solutions

### Option A: Wrap in rescue (Recommended)
```ruby
begin
  api_key.touch_last_used!
rescue ActiveRecord::ActiveRecordError => e
  Rails.logger.warn("Failed to update last_used_at for API key #{api_key.id}: #{e.message}")
end
```
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: `config/initializers/fast_mcp.rb`

## Acceptance Criteria
- [ ] DB write failure in `touch_last_used!` does not crash the request
- [ ] Warning logged on failure

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
