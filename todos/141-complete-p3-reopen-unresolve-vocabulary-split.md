---
status: pending
priority: p3
issue_id: "141"
tags: [code-review, quality, naming, pr-18]
dependencies: []
---

# "reopen" vs "unresolve" vocabulary split in codebase

## Problem Statement
The codebase uses "reopen" in models/DB (enum value `reopened`, method `reopen!`) but "unresolve" in the UI (button text "Unresolve", flash message "Annotation unresolved"). This vocabulary split can confuse developers and makes searching the codebase harder.

## Findings
- Model: `action: :reopened`, `reopen!` method
- UI: "Unresolve" button, "Annotation unresolved" flash message
- Controller: `reopen_action?` method
- Git history: Originally named "Not Fixed", renamed to "Unresolve" in commit 701230e
- Agents: kieran-rails-reviewer, pattern-recognition-specialist

## Proposed Solutions

### Option A: Standardize on "unresolve" everywhere
Rename `reopen!` → `unresolve!`, `reopened` enum → keep DB value but alias.
- **Pros**: Consistent vocabulary
- **Cons**: DB enum value change requires migration or mapping
- **Effort**: Medium
- **Risk**: Medium (enum value change)

### Option B: Accept the split (Recommended)
Keep "reopen" for internal/technical vocabulary and "unresolve" for user-facing copy. This is a common pattern (e.g., "destroy" internally, "delete" in UI).
- **Pros**: No code changes needed, common Rails pattern
- **Cons**: Slight confusion for new developers
- **Effort**: None
- **Risk**: None

## Acceptance Criteria
- [ ] Decision documented (either standardize or accept the split)
- [ ] If standardizing: consistent vocabulary across codebase

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2026-02-21 | Created from PR #18 review | Internal vs user-facing vocabulary split is common and acceptable |

## Resources
- PR #18: Add annotation comment threads with resolve/reopen functionality
