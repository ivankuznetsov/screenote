---
status: pending
priority: p3
issue_id: "036"
tags: [code-review, performance, css]
dependencies: ["027"]
---

# Mobile Performance Optimizations for Landing Page

## Problem Statement
Several CSS features on the landing page are GPU-expensive on mobile: `backdrop-filter: blur(12px)` on fixed nav (re-composites every scroll frame), full-viewport CSS grid patterns with mask-image, and a 600x600px glow element. These cause potential jank on lower-powered devices.

## Findings
- `.landing-nav`: `backdrop-filter: blur(12px)` without `will-change` hint
- `.hero__grid` and `.auth-shell__grid`: full-viewport gradient patterns with mask-image + opacity
- `.hero__glow`: 600x600px radial gradient with transform (GPU layer)
- Agents: performance-oracle (P2-P3)

## Proposed Solutions
1. Add `will-change: backdrop-filter` to `.landing-nav`
2. Hide decorative grid/glow on mobile: `@media (max-width: 768px) { .hero__grid, .hero__glow { display: none; } }`
3. Reduce blur radius from 12px to 8px (or use solid background on mobile)

- Effort: Small
- Risk: Low

## Technical Details
- **Affected files:** CSS file (landing section)
- **PR:** #6

## Acceptance Criteria
- [ ] Decorative elements optimized or hidden on mobile
- [ ] No visible scroll jank on mobile devices

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | backdrop-filter on fixed elements is expensive |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
