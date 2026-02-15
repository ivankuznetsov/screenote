---
status: pending
priority: p1
issue_id: "026"
tags: [code-review, css, cleanup]
dependencies: []
---

# Dead CSS: Old .auth-page and .btn--oauth Classes (62 Lines)

## Problem Statement
The old auth page styles at lines 345-407 of `application.css` are now completely unused. The auth views were redesigned with `.auth-card` classes, but the old `.auth-page`, `.auth-page__title`, `.auth-page__divider`, `.auth-page__links`, `.auth-page__oauth`, `.btn--oauth` classes were not removed. These 62 lines of dead code cause confusion about which auth styles are active.

## Findings
- `app/assets/stylesheets/application.css:345-407`: 7 CSS rules, ~62 lines, zero references in any view template
- `grep -r "auth-page\|btn--oauth" app/views/` returns zero matches
- Agents: pattern-recognition-specialist (P1), code-simplicity-reviewer (P1)

## Proposed Solutions

### Option A: Delete lines 345-407 (Recommended)
Remove the dead CSS block entirely.
- Pros: Clean, no confusion, -62 lines
- Cons: None
- Effort: Trivial
- Risk: None

## Technical Details
- **Affected files:** `app/assets/stylesheets/application.css`
- **PR:** #6

## Acceptance Criteria
- [ ] No `.auth-page` or `.btn--oauth` classes exist in CSS
- [ ] All views still render correctly
- [ ] Tests pass

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | Always clean up old styles when redesigning |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
