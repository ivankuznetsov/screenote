---
status: pending
priority: p2
issue_id: "031"
tags: [code-review, dry, rails]
dependencies: []
---

# Extract OAuth Buttons Into Shared Partial

## Problem Statement
The OAuth provider buttons block (12 lines) is copied verbatim between `sessions/new.html.erb` and `registrations/new.html.erb`. Any change (new provider, style update, accessibility fix) must be made in two places.

## Findings
- `app/views/rails_simple_auth/sessions/new.html.erb:9-22`: OAuth block
- `app/views/rails_simple_auth/registrations/new.html.erb:5-18`: Identical OAuth block
- Agents: pattern-recognition-specialist, dhh-rails-reviewer, code-simplicity-reviewer

## Proposed Solutions

### Option A: Extract to shared partial (Recommended)
Create `app/views/rails_simple_auth/shared/_oauth_buttons.html.erb` and render from both views.
- Pros: DRY, single source of truth, -12 lines
- Cons: None
- Effort: Small
- Risk: Low

## Technical Details
- **Affected files:** New partial, sessions/new.html.erb, registrations/new.html.erb
- **PR:** #6

## Acceptance Criteria
- [ ] Shared `_oauth_buttons.html.erb` partial exists
- [ ] Both views render the shared partial
- [ ] OAuth buttons work identically on both pages

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | Don't copy-paste ERB blocks |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
