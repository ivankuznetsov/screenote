---
status: ready
priority: p3
issue_id: "099"
tags: [code-review, rails-conventions, oauth]
dependencies: []
---

# Replace form_tag with form_with in Consent View

## Problem Statement
The OAuth consent view uses `form_tag` which is deprecated in modern Rails. Should use `form_with` instead for consistency with Rails conventions.

## Findings
- `app/views/doorkeeper/authorizations/new.html.erb`: Uses `form_tag` + raw `<select>` tag
- Should also replace raw `<select>` with `select_tag` + `options_from_collection_for_select`
- Agents: dhh-rails-reviewer, pattern-recognition-specialist

## Technical Details
- Affected files: `app/views/doorkeeper/authorizations/new.html.erb`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
