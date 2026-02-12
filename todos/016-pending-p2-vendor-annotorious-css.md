---
status: pending
priority: p2
issue_id: "016"
tags: [code-review, rails, reliability]
dependencies: []
---

# Vendor Annotorious CSS Instead of CDN

## Problem Statement
Annotorious CSS is loaded from jsdelivr CDN. If the CDN goes down, the annotation interface breaks. The JS is already pinned via importmap. CSS should also be vendored.

## Findings
- `app/views/screenshots/show.html.erb:2`: `<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@annotorious/annotorious@3.0.10/dist/annotorious.css">`
- No SRI hash on the link tag
- Agents: dhh-rails-reviewer (Finding 8), security-sentinel (L4)

## Proposed Solutions
Download the CSS to `vendor/assets` or `app/assets/stylesheets/vendor/` and serve via Propshaft.
- Effort: Small | Risk: Low

## Acceptance Criteria
- [ ] Annotorious CSS served locally, not from CDN
- [ ] Annotation interface still renders correctly

## Work Log
- 2026-02-12: Created from code review (dhh-rails-reviewer, security-sentinel)
