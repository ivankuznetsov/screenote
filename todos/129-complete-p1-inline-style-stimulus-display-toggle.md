---
status: pending
priority: p1
issue_id: "129"
tags: [code-review, conventions, css, stimulus, pr-18]
dependencies: []
---

# Inline style and JS style.display manipulation violates project rules

## Problem Statement
The annotation thread form uses `style="display: none;"` inline and the Stimulus controller toggles via `wrapper.style.display`. This violates two project rules: "never use inline styles" (CLAUDE.md) and "never use javascript logic where we can use native turbo logic". The `<details>` HTML element or a CSS class toggle would be more Rails-idiomatic.

## Findings
- `app/views/annotations/_annotation.html.erb` line 66: `style="display: none;"`
- `app/javascript/controllers/annotation_thread_controller.js`: `wrapper.style.display = wrapper.style.display === "none" ? "block" : "none"`
- CLAUDE.md explicitly states: "No inline styles" and "No JS alerts — use proper UI notifications"
- A `<details>/<summary>` element or a CSS hidden class with `classList.toggle` would be cleaner
- Agents: kieran-rails-reviewer, dhh-rails-reviewer, architecture-strategist, pattern-recognition-specialist, security-sentinel

## Proposed Solutions

### Option A: Use <details> element (Recommended)
Replace the button + hidden div with a native `<details>` element:
```erb
<details class="annotation-thread__form-wrapper" data-testid="unresolve-form">
  <summary class="btn btn--small btn--warning" data-testid="unresolve-button">Unresolve</summary>
  <%= form_with ... %>
</ details>
```
- **Pros**: Zero JavaScript needed, native HTML toggle, accessible, no inline styles
- **Cons**: Styling `<summary>` requires some CSS
- **Effort**: Small
- **Risk**: Low

### Option B: CSS class toggle
Add a `.hidden` utility class and toggle it with `classList.toggle("hidden")`.
- **Pros**: Simple, familiar pattern
- **Cons**: Still needs Stimulus controller
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] No `style=` attributes in the annotation partial
- [ ] No `element.style.display` in JavaScript
- [ ] Unresolve form toggle still works correctly
- [ ] All existing tests pass

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Prefer native HTML elements over JS for simple show/hide |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
- CLAUDE.md: "No inline styles", "use native Turbo logic instead of custom JavaScript"
