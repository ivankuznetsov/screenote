---
status: pending
priority: p3
issue_id: "021"
tags: [code-review, security]
dependencies: []
---

# Escape JavaScript Interpolated Values in Honeybadger Snippet

## Problem Statement
`app/views/layouts/application.html.erb` interpolates ENV values into a `<script>` tag without escaping. If `KAMAL_VERSION` contains a single quote, it could break JS or enable XSS.

## Proposed Solutions
Use `j()` (escape_javascript) for interpolated values:
```erb
apiKey: '<%= j(ENV["HONEYBADGER_JS_API_KEY"].to_s) %>'
```
- Effort: Small | Risk: Low

## Work Log
- 2026-02-12: Created from code review (security-sentinel L1)
