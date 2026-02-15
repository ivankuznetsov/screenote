---
status: pending
priority: p1
issue_id: "038"
tags: [code-review, javascript, race-condition, frontend]
dependencies: []
---

# Wait for image load before initializing Annotorious

## Problem Statement

`annotorious_controller.js:connect()` calls `initAnnotorious()` immediately without waiting for the image to load. On slow connections, Annotorious gets a 0x0 canvas because `naturalWidth`/`naturalHeight` are 0, causing all coordinate calculations to produce `NaN` or `Infinity`.

## Findings

- `connect()` at line 7-12 calls `initAnnotorious()` and `renderExistingPins()` synchronously
- `parseSelector()` at line 57-83 divides by `naturalW`/`naturalH` — division by zero when image not loaded
- `createImageAnnotator()` may receive a 0x0 element, producing a broken overlay
- This is a **pre-existing bug**, not introduced by the data-testid PR, but it's critical for production reliability

**Identified by:** Frontend Races Reviewer (Julik)

## Proposed Solutions

### Option 1: Check image.complete with load fallback (Recommended)

**Approach:** Check `imageTarget.complete` before init; if not loaded, listen for `load` event.

```javascript
connect() {
  if (!this.hasImageTarget) return

  if (this.imageTarget.complete && this.imageTarget.naturalWidth > 0) {
    this.initAnnotorious()
    this.renderExistingPins()
  } else {
    this.imageTarget.addEventListener("load", () => {
      this.initAnnotorious()
      this.renderExistingPins()
    }, { once: true })
  }
}
```

**Pros:**
- Simple, minimal change
- Handles both cached (already complete) and uncached images
- `{ once: true }` prevents listener leak

**Cons:**
- If image fails to load, annotorious never inits (acceptable — no canvas to annotate)

**Effort:** 30 minutes

**Risk:** Low

---

### Option 2: Retry with requestAnimationFrame

**Approach:** Poll until `naturalWidth > 0` using rAF loop.

**Pros:**
- Works even with unusual image loading patterns

**Cons:**
- More complex, potential for infinite loop if image never loads
- Overkill for this scenario

**Effort:** 1 hour

**Risk:** Medium

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `app/javascript/controllers/annotorious_controller.js:7-12` - connect() method
- `app/javascript/controllers/annotorious_controller.js:57-83` - parseSelector() (downstream impact)

## Resources

- **PR:** #7
- **Annotorious v3 docs:** https://annotorious.dev

## Acceptance Criteria

- [ ] Annotorious only initializes after image is fully loaded
- [ ] Cached images (already complete) still work instantly
- [ ] Coordinate calculations never produce NaN/Infinity
- [ ] Annotation pins render correctly on slow connections
- [ ] No listener leaks on disconnect

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Frontend Races Reviewer)

**Actions:**
- Identified race condition in connect() → initAnnotorious() flow
- Confirmed naturalWidth/naturalHeight are 0 before image load
- Proposed load event listener solution

**Learnings:**
- Stimulus `connect()` fires when element is in DOM, not when resources are loaded
- Always check `image.complete` before reading natural dimensions
