---
status: pending
priority: p2
issue_id: "015"
tags: [code-review, security, data-integrity]
dependencies: []
---

# Add Length Validations on Comment, Name, and Title Fields

## Problem Statement
Several text fields have no length limit: `Annotation.comment`, `ApiKey.name`, `Screenshot.title`. A malicious user could submit millions of characters, causing storage issues and slow renders.

## Findings
- `app/models/annotation.rb`: comment has no length validation
- `app/models/api_key.rb:9`: name has presence only, no length
- `app/models/screenshot.rb`: title has presence only, no length
- `Project` model correctly has `length: { maximum: 255 }` on name
- Agents: security-sentinel (M2, L2), data-integrity-guardian

## Proposed Solutions
Add `length: { maximum: N }` validations.
- Effort: Small | Risk: Low

## Acceptance Criteria
- [ ] All text fields have reasonable max length validations
- [ ] Tests verify length validation

## Work Log
- 2026-02-12: Created from code review (security-sentinel, data-integrity-guardian)
