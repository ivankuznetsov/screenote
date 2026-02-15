---
status: complete
priority: p3
issue_id: "079"
tags: [code-review, css, design-tokens]
dependencies: []
---

# Hardcoded #ffffff in help.css Instead of CSS Variable

## Problem Statement
`help.css` uses hardcoded `#ffffff` for backgrounds instead of using the `--color-white` or similar CSS custom property from the design token system in `application.css`. This breaks theming consistency.

## Findings
- **Location**: `app/assets/stylesheets/help.css` (multiple occurrences of `#ffffff`)
- Application uses CSS custom properties (`--color-*`) for theming
- help.css bypasses the token system
- Found by pattern-recognition-specialist

## Proposed Solutions

### Option 1: Replace with CSS Variable (Recommended)
- **Pros**: Consistent theming, follows existing pattern
- **Cons**: Need to define `--color-white` if not exists
- **Effort**: Small
- **Risk**: Low

## Recommended Action
Define `--color-white: #ffffff` in `:root` and replace hardcoded values in help.css. Optionally fix the 10+ occurrences in application.css too for full consistency.

## Technical Details
- **Affected Files**: `app/assets/stylesheets/help.css`
- **Database Changes**: No

## Acceptance Criteria
- [ ] No hardcoded color values in help.css
- [ ] Uses CSS custom properties consistently

## Work Log

### 2026-02-15 - Approved for Work
**By:** Claude Triage System
**Actions:**
- Issue approved during triage session
- Status changed from pending to ready

### 2026-02-15 - Identified in Code Review
**By:** Multi-agent review (PR #10)

## Resources
- PR #10: Add MCP help page and dashboard banner
