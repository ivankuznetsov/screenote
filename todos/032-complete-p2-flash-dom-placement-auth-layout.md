---
status: pending
priority: p2
issue_id: "032"
tags: [code-review, rails, html]
dependencies: []
---

# Flash Messages DOM Placement in Auth Layout

## Problem Statement
In `auth.html.erb`, flash messages are rendered inside `.auth-shell__main` (a flex container centered with `align-items: center`). The CSS overrides flash to `position: fixed`, making the DOM position semantically misleading — someone reading the markup would assume flash messages are contextual to the form area. The landing layout correctly places flash messages outside the main content container.

## Findings
- `app/views/layouts/auth.html.erb:36-41`: Flash messages inside `.auth-shell__main`
- CSS `.auth-body .flash` uses `position: fixed; top: 1rem` — float regardless of DOM position
- Agents: kieran-rails-reviewer (P1)

## Proposed Solutions

### Option A: Move flash outside `.auth-shell` (Recommended)
Move flash rendering to `<body>` level, before `.auth-shell`, matching the landing layout pattern.
- Pros: DOM reflects visual intent, consistent with landing layout
- Cons: Minor markup change
- Effort: Trivial
- Risk: Low

## Technical Details
- **Affected files:** `app/views/layouts/auth.html.erb`
- **PR:** #6

## Acceptance Criteria
- [ ] Flash messages rendered outside `.auth-shell` div
- [ ] Flash messages still appear correctly with fixed positioning

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | DOM structure should match visual intent |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
