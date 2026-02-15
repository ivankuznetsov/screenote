---
status: pending
priority: p2
issue_id: "039"
tags: [code-review, javascript, race-condition, frontend]
dependencies: []
---

# Clear pendingAnnotationId when form is cancelled

## Problem Statement

`pendingAnnotationId` is set in `handleCreate()` but never cleared when the user cancels the annotation form. If the user draws at the same coordinates again, the duplicate check (`if (this.pendingAnnotationId === annotation.id) return`) could swallow the new annotation.

## Findings

- `handleCreate()` at line 42-44 sets `this.pendingAnnotationId = annotation.id`
- `cancelForm()` at line 100-104 only removes the DOM element, doesn't clear the ID
- If Annotorious reuses the same ID for a new annotation at same coords, it would be silently ignored

**Identified by:** Frontend Races Reviewer (Julik)

## Proposed Solutions

### Option 1: Clear in cancelForm() (Recommended)

**Approach:** Add `this.pendingAnnotationId = null` to `cancelForm()`.

**Effort:** 5 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `app/javascript/controllers/annotorious_controller.js:100-104` - cancelForm()

## Acceptance Criteria

- [ ] pendingAnnotationId cleared on cancel
- [ ] User can draw annotation at same location after cancelling

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Frontend Races Reviewer)
