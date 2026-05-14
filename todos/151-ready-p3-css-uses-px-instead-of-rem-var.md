---
status: ready
priority: p3
issue_id: "151"
tags: [code-review, css, conventions]
dependencies: []
---

# CSS uses px values instead of rem and CSS variables

## Problem Statement
New autocomplete styles use raw `px` values and hardcoded border-radius instead of `rem` units and `var(--radius)` used throughout the existing stylesheet.

## Findings
- **Source**: Kieran Rails Reviewer
- **Location**: `app/assets/stylesheets/application.css` lines 1107-1137
- `border-radius: 8px` should be `var(--radius)`, padding should use rem

## Acceptance Criteria
- [ ] Border-radius uses CSS variable
- [ ] Padding values use rem units
