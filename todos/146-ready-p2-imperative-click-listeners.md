---
status: ready
priority: p2
issue_id: "146"
tags: [code-review, javascript, stimulus, conventions]
dependencies: []
---

# Imperative click listeners instead of Stimulus data-action

## Problem Statement
After each fetch, click listeners are imperatively attached to `<li>` elements via `addEventListener`. The Stimulus-idiomatic approach is to use `data-action` attributes in the server-rendered partial HTML.

## Findings
- **Source**: DHH, Kieran, Architecture (all 3 flagged)
- **Location**: `app/javascript/controllers/email_autocomplete_controller.js:49-52`

## Proposed Solutions
### Option A: Add data-action to partial HTML (Recommended)
In `_suggestions.html.erb`, add `data-action="click->email-autocomplete#selectItem"` to each `<li>`. Add a `selectItem(event)` method. Remove the `addEventListener` loop.
- **Effort**: Small | **Risk**: None

## Acceptance Criteria
- [ ] No imperative addEventListener calls in fetchSuggestions
- [ ] Click handling uses Stimulus data-action in partial
- [ ] Clicking a suggestion still fills the email field
