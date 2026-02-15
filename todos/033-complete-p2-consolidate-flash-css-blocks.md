---
status: pending
priority: p2
issue_id: "033"
tags: [code-review, css, dry]
dependencies: ["027"]
---

# Consolidate Duplicated Flash CSS Blocks

## Problem Statement
Two nearly identical 9-line CSS blocks override `.flash` positioning for `.auth-body` and `.landing-body`. The only difference is the `top` value (1rem vs 5rem). This is 8 lines of unnecessary duplication.

## Findings
- `application.css:1270-1279`: `.auth-body .flash` block
- `application.css:1596-1605`: `.landing-body .flash` block (identical except `top: 5rem`)
- Agents: pattern-recognition-specialist (P1), code-simplicity-reviewer

## Proposed Solutions

### Option A: Combined selector with override (Recommended)
```css
.landing-body .flash, .auth-body .flash {
  position: fixed; left: 50%; transform: translateX(-50%);
  z-index: 200; max-width: 480px; width: calc(100% - 2rem);
  border-radius: 8px; top: 1rem;
}
.landing-body .flash { top: 5rem; }
```
- Pros: DRY, -8 lines
- Cons: None
- Effort: Trivial
- Risk: None

## Technical Details
- **Affected files:** CSS file (application.css or landing.css/auth.css after split)
- **PR:** #6

## Acceptance Criteria
- [ ] Single shared flash rule with per-context override
- [ ] Flash messages appear correctly on both landing and auth pages

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | Consolidate near-duplicate CSS rules |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
