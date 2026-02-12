---
status: pending
priority: p3
issue_id: "020"
tags: [code-review, simplicity]
dependencies: []
---

# Remove YAGNI Code and Low-Value Tests

## Problem Statement
Several pieces of code are premature optimization or unused:
- `ApiKey#revoked?` is redundant (use `revoked_at?`)
- `resolved_by_user` association declared but never assigned
- Crop service caching may be premature (Vips is fast)
- Low-value tests: enum values, association existence, delegation

## Findings
- `app/models/api_key.rb:27-29`: `revoked?` duplicates `revoked_at?`
- `app/models/annotation.rb:5`: `resolved_by_user` never used
- `app/services/annotation_crop_service.rb:18-20`: Cache stores base64 in Solid Cache (DB)
- Tests: `annotation_test.rb:136-148,157-160`, `screenshot_test.rb:56-60`, `crop_service_test.rb:37-42`
- Agents: simplicity-reviewer

## Proposed Solutions
Remove the identified code. ~43 LOC reduction.
- Effort: Small | Risk: Low

## Work Log
- 2026-02-12: Created from code review (simplicity-reviewer)
