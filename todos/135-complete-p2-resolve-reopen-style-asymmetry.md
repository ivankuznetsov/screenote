---
status: pending
priority: p2
issue_id: "135"
tags: [code-review, quality, model, pr-18]
dependencies: []
---

# resolve! and reopen! have asymmetric implementation styles

## Problem Statement
`resolve!` uses `assign_attributes` + `save!` while `reopen!` uses `update!`. Both are wrapped in transactions but follow different patterns, making the code harder to read and maintain. They should use the same style.

## Findings
- `resolve!`: `assign_attributes(status: :resolved, ...)` then `save!`
- `reopen!`: `update!(status: :open, resolved_by_user: nil, resolved_by_api_key: nil)`
- Both create an `annotation_comments` record inside a transaction
- `resolve!` accepts both `user:` and `api_key:` kwargs; `reopen!` only accepts `user:`
- Agents: kieran-rails-reviewer, dhh-rails-reviewer, pattern-recognition-specialist, code-simplicity-reviewer

## Proposed Solutions

### Option A: Standardize on update! style (Recommended)
Rewrite both methods to use the same pattern:
```ruby
def resolve!(user: nil, api_key: nil, body: "Marked as resolved")
  transaction do
    update!(status: :resolved, resolved_by_user: user, resolved_by_api_key: api_key)
    annotation_comments.create!(user: user, api_key: api_key, body: body, action: :resolved)
  end
end

def reopen!(user: nil, api_key: nil, body:)
  transaction do
    update!(status: :open, resolved_by_user: nil, resolved_by_api_key: nil)
    annotation_comments.create!(user: user, api_key: api_key, body: body, action: :reopened)
  end
end
```
- **Pros**: Consistent, readable, symmetric
- **Cons**: Minor refactor
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Both methods use the same update pattern
- [ ] Both methods accept the same kwargs (user: and api_key:)
- [ ] All existing tests pass

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Symmetric operations should have symmetric implementations |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
