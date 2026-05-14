---
status: pending
priority: p1
issue_id: "130"
tags: [code-review, data-integrity, model, pr-18]
dependencies: []
---

# No guard against reopening an already-open annotation

## Problem Statement
`Annotation#reopen!` does not check whether the annotation is currently `resolved` before reopening it. Calling `reopen!` on an already-open annotation will create a misleading "reopened" comment in the thread without changing any actual status. This could be triggered by double-clicking the unresolve button or via a crafted API request.

## Findings
- `app/models/annotation.rb`: `reopen!` method has no `resolved?` guard
- `resolve!` also lacks an `open?` guard (symmetric issue but less impactful)
- The controller does check `reopen_action?` but doesn't verify annotation state
- Multiple spurious "reopened" comments would confuse the audit trail
- Agents: kieran-rails-reviewer, dhh-rails-reviewer, architecture-strategist, pattern-recognition-specialist, data-integrity-guardian

## Proposed Solutions

### Option A: Add guard clauses to both methods (Recommended)
```ruby
def reopen!(user:, body:)
  raise InvalidTransitionError, "Annotation is not resolved" unless resolved?
  # ...existing code...
end

def resolve!(user: nil, api_key: nil, body: "Marked as resolved")
  raise InvalidTransitionError, "Annotation is not open" unless open?
  # ...existing code...
end
```
- **Pros**: Prevents invalid state transitions, clear error messages
- **Cons**: Need to define custom error class (or use ActiveRecord::RecordInvalid)
- **Effort**: Small
- **Risk**: Low

### Option B: Silent no-op with return
```ruby
def reopen!(user:, body:)
  return unless resolved?
  # ...
end
```
- **Pros**: Simpler, no error handling needed
- **Cons**: Silently ignoring bad input hides bugs
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] `reopen!` raises or returns early when annotation is already open
- [ ] `resolve!` raises or returns early when annotation is already resolved
- [ ] No spurious "reopened" comments created for already-open annotations
- [ ] Controller handles the error gracefully with a user-friendly message
- [ ] Test covers attempting to reopen an already-open annotation

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | State machine transitions should always validate preconditions |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
- `app/models/annotation.rb`
