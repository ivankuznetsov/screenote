---
status: complete
priority: p3
issue_id: "123"
tags: [code-review, rails, simplicity, pr-11]
dependencies: []
---

# Remove `prefix: true` from Status Enum and Simplify `pro?` Method

## Problem Statement
The `status` enum uses `prefix: true` generating awkward `status_active?`, `status_past_due?` methods. The plan values (`free`, `pro`) and status values (`incomplete`, `active`, `past_due`, `canceled`) do not collide, so the prefix is unnecessary. Additionally, `pro?` uses `|| false` which is redundant in Ruby boolean context.

## Findings
- **File**: `app/models/subscription.rb`, line 7 (`prefix: true`)
- **File**: `app/models/user.rb`, line 17 (`|| false`)
- Identified by: Code Simplicity Reviewer
- Removing prefix would change `status_active?` to `active?`, `active_pro?` to `pro? && active?`

## Proposed Solutions

### Option A: Remove prefix, simplify methods
- Remove `prefix: true` from status enum
- Update all `status_active?` calls to `active?`
- Remove `|| false` from `pro?`
- **Effort**: Small (touches ~15 call sites)
- **Risk**: Low

## Acceptance Criteria
- [ ] Enum methods read naturally (`active?` instead of `status_active?`)
- [ ] All references updated
- [ ] Tests pass

## Work Log
- 2026-02-16: Created from PR #11 code review
