---
status: complete
priority: p2
issue_id: "066"
tags: [code-review, ux, performance, stimulus]
dependencies: []
---

# Banner Flash-of-Content (CLS) on Dismissed State

## Problem Statement

When the MCP banner has been dismissed, it still renders in HTML and is only removed by JavaScript in the Stimulus `connect()` callback. This causes a visible flash (CLS - Cumulative Layout Shift) on every page load for users who already dismissed the banner.

## Findings

- `dismissible_controller.js` calls `this.element.remove()` in `connect()`
- Banner HTML is always server-rendered regardless of dismissal state
- The flash is brief but measurable as CLS
- Turbo Drive page cache may also replay the flash on back-navigation
- Source: Frontend races reviewer

## Proposed Solutions

### Option A: CSS `hidden` attribute with Stimulus class toggle
- **Pros**: No CLS — element starts hidden, only shown if not dismissed
- **Cons**: Slightly different pattern (show-on-connect vs remove-on-connect)
- **Effort**: Small
- **Risk**: Low

### Option B: Server-side cookie check to skip rendering
- **Pros**: No JS dependency, zero CLS
- **Cons**: Requires cookie management, mixes server/client state
- **Effort**: Medium
- **Risk**: Low

## Technical Details

- **Affected files**: `app/javascript/controllers/dismissible_controller.js`, `app/views/projects/index.html.erb`
- **Components**: Stimulus controller, banner partial

## Acceptance Criteria

- [ ] No visible flash when banner is already dismissed
- [ ] Banner still dismissible on first view
- [ ] Works correctly with Turbo Drive page cache
