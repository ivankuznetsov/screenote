---
status: pending
priority: p3
issue_id: "142"
tags: [code-review, quality, testing, pr-18]
dependencies: []
---

# Fixture uses magic number for action enum

## Problem Statement
The `annotation_comments` fixture uses `action: 1` instead of the symbolic enum name. Magic numbers are fragile — if the enum order changes, the fixture silently breaks. Rails fixtures support string enum values.

## Findings
- `test/fixtures/annotation_comments.yml`: `action: 1` (should be `action: resolved`)
- Rails fixtures can use enum string values directly
- Other fixtures in the project may have the same issue
- Agents: kieran-rails-reviewer, pattern-recognition-specialist

## Proposed Solutions

### Option A: Use symbolic name (Recommended)
```yaml
resolved_comment:
  action: resolved  # instead of action: 1
```
- **Pros**: Self-documenting, resilient to enum reordering
- **Cons**: None
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] All enum values in fixtures use symbolic names, not integers

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Always use symbolic enum names in fixtures |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
