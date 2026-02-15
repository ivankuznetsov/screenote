---
status: pending
priority: p1
issue_id: "037"
tags: [code-review, git, blocker]
dependencies: []
---

# Rebase e2e-tests branch onto main to prevent landing page revert

## Problem Statement

The `feature/e2e-tests` branch was cut before `146c748` (Merge feature/landing). Merging this branch will **revert** the entire landing page and auth redesign that was merged to main. This is the highest-priority finding — it blocks merge entirely.

## Findings

- Branch is missing all changes from `146c748 Merge feature/landing: Add landing page and redesign auth pages`
- Files that would be deleted on merge: `pages_controller.rb`, `landing.html.erb`, landing layout, `auth.css`, `landing.css`, all custom auth view overrides
- Config that would revert: `routes.rb`, `rails_simple_auth.rb`, `content_security_policy.rb`
- The `_head.html.erb` partial on feature branch is a simpler version; main already has one with `local_assigns.fetch(:default_title, ...)` flexibility
- `auth.html.erb` on feature branch is missing the cinematic dark-theme redesign
- `lang="en"` attribute lost from `<html>` tag (accessibility/SEO regression)
- `dashboard_path` → `root_path` change may conflict with main's routing

**Identified by:** Kieran Rails Reviewer, DHH Rails Reviewer, Data Integrity Guardian, Performance Oracle

## Proposed Solutions

### Option 1: Rebase onto main (Recommended)

**Approach:** `git rebase main` on the feature branch, resolving conflicts to keep both landing page and data-testid changes.

**Pros:**
- Clean linear history
- Ensures all main changes preserved
- Conflict resolution happens once

**Cons:**
- May have merge conflicts in shared files (layouts, routes)
- Requires force-push to feature branch

**Effort:** 1-2 hours

**Risk:** Medium (conflict resolution needed)

---

### Option 2: Merge main into feature branch

**Approach:** `git merge main` into feature/e2e-tests.

**Pros:**
- Preserves branch history
- No force-push needed

**Cons:**
- Creates merge commit
- Still requires conflict resolution

**Effort:** 1-2 hours

**Risk:** Medium

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files (conflicts expected):**
- `app/views/layouts/application.html.erb`
- `app/views/layouts/auth.html.erb`
- `app/views/layouts/_head.html.erb`
- `config/routes.rb`
- `config/initializers/rails_simple_auth.rb`
- `config/initializers/content_security_policy.rb`

**Key concerns during rebase:**
- Ensure `lang="en"` is restored on `<html>` tag
- Ensure data-testid attributes are added to the NEW auth layout (cinematic theme)
- Ensure `_head.html.erb` uses main's version with `local_assigns.fetch`
- Verify landing page routes remain intact

## Resources

- **PR:** #7
- **Merge commit on main:** 146c748

## Acceptance Criteria

- [ ] Branch rebased onto current main
- [ ] Landing page (`/`) works correctly
- [ ] Auth pages use cinematic dark theme
- [ ] All data-testid attributes present on new layout
- [ ] `lang="en"` present on `<html>` tag
- [ ] All E2E tests still pass
- [ ] All unit tests still pass (147 tests)

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (compound-engineering:workflows:review)

**Actions:**
- Identified stale branch via multiple review agents
- Confirmed branch was cut before landing page merge
- Cataloged all files/config that would be reverted

**Learnings:**
- Long-lived feature branches must be rebased regularly
- Layout files are high-conflict zones
