---
status: pending
priority: p2
issue_id: "028"
tags: [code-review, css, maintainability]
dependencies: []
---

# Auth CSS Section Uses 35+ Hardcoded Hex Colors Instead of CSS Variables

## Problem Statement
The landing section correctly defines CSS custom properties (`--landing-bg`, `--landing-surface`, etc.) and uses them throughout. The auth section (lines 1263-1605) hardcodes the exact same color values as raw hex literals 35+ times. Changing the accent color requires editing 4+ places in auth vs 1 variable in landing.

## Findings
- `#0a0a0f` (--landing-bg): 7 occurrences in auth section
- `#e8e8ed` (--landing-text): 10 occurrences
- `#13131a` (--landing-surface): 3 occurrences
- `#1e1e2a` (--landing-border): 5 occurrences
- `#e5a31e` (--landing-accent): 4 occurrences
- `#2a2a38`, `#8888a0`, `#b0b0c0`: additional occurrences
- Agents: ALL agents flagged this

## Proposed Solutions

### Option A: Define shared dark theme variables (Recommended)
Define CSS custom properties on both `.landing-body` and `.auth-body` (or a shared scope) and replace all hardcoded hex values with `var()` references.
```css
.landing-body, .auth-body {
  --dark-bg: #0a0a0f;
  --dark-surface: #13131a;
  --dark-border: #1e1e2a;
  --dark-text: #e8e8ed;
  --dark-text-dim: #8888a0;
  --dark-accent: #e5a31e;
}
```
- Pros: Single source of truth, easy theming, -15 LOC
- Cons: Minor refactor
- Effort: Low-Medium
- Risk: Low

## Technical Details
- **Affected files:** `app/assets/stylesheets/application.css` (or `auth.css` after split)
- **PR:** #6

## Acceptance Criteria
- [ ] Auth section uses CSS variables, not hardcoded hex values
- [ ] Shared dark theme variables defined once
- [ ] Visual appearance unchanged

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | Always use CSS variables for shared color palettes |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
