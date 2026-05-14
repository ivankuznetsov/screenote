---
status: pending
priority: p3
issue_id: "168"
tags: [code-review, multi-viewport, pr-5, cleanup]
dependencies: []
---

# Drop DB + model default on `Annotation.viewport` after PR-3 ships

## Problem Statement
PR-1 added `annotations.viewport` with `NOT NULL DEFAULT 0` to auto-backfill existing rows to `:desktop`. Once PR-3 ships the UI + MCP tool that always writes `viewport` explicitly, the default becomes a silent-write footgun: any future caller that forgets to pass viewport will default to `:desktop` without error.

PR-5 (the cleanup PR after PR-3 stabilizes) should:
1. Drop the DB default (`change_column_default :annotations, :viewport, from: 0, to: nil`)
2. Remove `default: :desktop` from the `Annotation` model's viewport enum
3. Add `validates :viewport, presence: true` (redundant with NOT NULL but gives clear validation errors)

## Findings
- **Source**: Data Integrity Guardian review of PR #28
- **Location**: `db/migrate/20260421110955_add_viewport_to_annotations.rb:10`, `app/models/annotation.rb:11`

## Acceptance Criteria
- [ ] Migration removes DB default
- [ ] Model no longer declares `default: :desktop`
- [ ] Attempting to create an Annotation without viewport raises a clear validation error (not silently writes desktop)
- [ ] All existing call sites pass viewport explicitly (PR-3 must have done this; PR-5 just verifies)
