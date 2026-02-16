---
status: pending
priority: p2
issue_id: "041"
tags: [code-review, javascript, race-condition, frontend]
dependencies: []
---

# Add disposed guard for post-disconnect callbacks in annotorious controller

## Problem Statement

After `disconnect()` destroys the annotorious instance, stale closures from `selectionChanged` or `createAnnotation` events could still fire, calling methods on a destroyed controller.

## Findings

- `disconnect()` at line 14-19 calls `this.anno.destroy()` and `removePins()`
- Event callbacks registered in `initAnnotorious()` (lines 29-39) hold closure references
- If an async event fires after disconnect, `this.handleCreate()` runs on stale state
- Edge case but can cause console errors or unexpected DOM manipulation

**Identified by:** Frontend Races Reviewer (Julik)

## Proposed Solutions

### Option 1: Add disposed flag (Recommended)

**Approach:** Set `this.disposed = true` in `disconnect()`, check at top of `handleCreate()`.

```javascript
disconnect() {
  this.disposed = true
  if (this.anno) this.anno.destroy()
  this.removePins()
}

handleCreate(annotation) {
  if (this.disposed) return
  // ... existing logic
}
```

**Effort:** 15 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `app/javascript/controllers/annotorious_controller.js:14-19` - disconnect()
- `app/javascript/controllers/annotorious_controller.js:42-55` - handleCreate()

## Acceptance Criteria

- [ ] No console errors when navigating away during annotation
- [ ] Disposed flag prevents stale callback execution

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Frontend Races Reviewer)
