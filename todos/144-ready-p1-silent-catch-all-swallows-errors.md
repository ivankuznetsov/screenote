---
status: ready
priority: p1
issue_id: "144"
tags: [code-review, javascript, error-handling]
dependencies: []
---

# Silent catch-all swallows all fetch errors with no logging

## Problem Statement
The catch block in `fetchSuggestions` catches every error type. Non-AbortError exceptions are silently swallowed — `this.close()` is called with no console logging, no user feedback. Network failures, TypeErrors, DOMExceptions all result in the dropdown silently closing. Users cannot distinguish "no results" from "server is down." Developers have zero client-side evidence of failures.

## Findings
- **Source**: Silent Failure Hunter (CRITICAL severity)
- **Location**: `app/javascript/controllers/email_autocomplete_controller.js:56-58`
- Also: non-200 responses (429 rate limit, 500 server error, 401 expired session) are all treated identically — silent close on line 39

## Proposed Solutions

### Option A: Add console.error for non-AbortError exceptions (Recommended)
- **Pros**: Minimal change, gives developers visibility
- **Cons**: Users still see no feedback
- **Effort**: Small
- **Risk**: None

### Option B: Show inline error message for persistent failures
- **Pros**: Better UX, users know the feature is broken
- **Cons**: More code, need error UI
- **Effort**: Medium
- **Risk**: Low

## Technical Details
- **Affected files**: `app/javascript/controllers/email_autocomplete_controller.js`

## Acceptance Criteria
- [ ] Non-AbortError exceptions are logged to console.error
- [ ] 429 rate limit responses are distinguishable from "no results"
- [ ] Server errors (500) are logged to console
