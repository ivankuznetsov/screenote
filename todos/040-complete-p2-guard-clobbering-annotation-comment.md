---
status: pending
priority: p2
issue_id: "040"
tags: [code-review, javascript, ux, frontend]
dependencies: []
---

# Guard against clobbering in-progress annotation comment

## Problem Statement

If a user is typing a comment in the annotation form and accidentally clicks the canvas, `showAnnotationForm()` calls `cancelForm()` first, destroying the in-progress text. There's no confirmation or protection.

## Findings

- `showAnnotationForm()` at line 85-98 unconditionally calls `cancelForm()` which removes existing form
- User's typed text is lost without warning
- This is a pre-existing UX issue, not introduced by data-testid PR

**Identified by:** Frontend Races Reviewer (Julik)

## Proposed Solutions

### Option 1: Guard check before cancel (Recommended)

**Approach:** Check if comment field has text before cancelling. If so, either skip the new annotation or show confirmation.

```javascript
showAnnotationForm(coords) {
  if (this.hasFormTarget && this.commentTarget.value.trim() !== "") {
    return // Don't clobber in-progress comment
  }
  this.cancelForm()
  // ... rest of method
}
```

**Pros:**
- Simple, prevents data loss
- User can finish current annotation first

**Cons:**
- Silently ignores new click (may confuse user)

**Effort:** 30 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `app/javascript/controllers/annotorious_controller.js:85-98` - showAnnotationForm()

## Acceptance Criteria

- [ ] In-progress comment text not destroyed by accidental canvas click
- [ ] User can still create new annotations when no form is open

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Frontend Races Reviewer)
