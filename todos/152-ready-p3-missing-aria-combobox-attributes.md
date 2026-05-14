---
status: ready
priority: p3
issue_id: "152"
tags: [code-review, accessibility]
dependencies: []
---

# Missing ARIA combobox attributes on input element

## Problem Statement
The `<ul>` has `role="listbox"` but the input lacks `role="combobox"`, `aria-expanded`, `aria-autocomplete="list"`, and `aria-activedescendant`. Incomplete ARIA combobox pattern.

## Findings
- **Source**: Architecture Strategist
- **Location**: `app/views/project_memberships/index.html.erb:15` and `app/javascript/controllers/email_autocomplete_controller.js`

## Acceptance Criteria
- [ ] Input has role="combobox" and aria-autocomplete="list"
- [ ] aria-expanded toggles with dropdown visibility
- [ ] aria-activedescendant updates on keyboard navigation
