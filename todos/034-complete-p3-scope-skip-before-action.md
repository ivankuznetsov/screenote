---
status: pending
priority: p3
issue_id: "034"
tags: [code-review, security, rails]
dependencies: []
---

# Scope skip_before_action to only: [:landing]

## Problem Statement
`PagesController` uses a blanket `skip_before_action :require_authentication` at the class level. Currently only one action exists (`landing`), so it's functionally equivalent. But if a developer adds actions in the future, they'll bypass auth by default without explicit thought.

## Findings
- `app/controllers/pages_controller.rb:4`: `skip_before_action :require_authentication` (no `only:`)
- Agents: security-sentinel (P1), kieran-rails-reviewer (P3)

## Proposed Solutions

### Option A: Scope with `only:` (Recommended)
```ruby
skip_before_action :require_authentication, only: [:landing]
```
- Pros: Explicit, prevents accidental auth bypass
- Effort: Trivial
- Risk: None

## Technical Details
- **Affected files:** `app/controllers/pages_controller.rb`
- **PR:** #6

## Acceptance Criteria
- [ ] `skip_before_action` scoped to `only: [:landing]`

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | Always scope auth bypass explicitly |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
