---
status: pending
priority: p3
issue_id: "022"
tags: [code-review, rails]
dependencies: []
---

# Use Rails Route Helpers for APP_HOST Instead of ENV.fetch

## Problem Statement
`ENV.fetch("APP_HOST", "localhost:3005")` is duplicated in 2 tool files. Production already sets `default_url_options`. Use route helpers instead.

## Proposed Solutions
Use `Rails.application.routes.url_helpers.root_url` or derive from `default_url_options`.
- Effort: Small | Risk: Low

## Work Log
- 2026-02-12: Created from code review (dhh-rails-reviewer, pattern-recognition)
