---
status: pending
priority: p2
issue_id: "047"
tags: [code-review, accessibility, seo]
dependencies: ["037"]
---

# Restore lang="en" on html tag

## Problem Statement

The `<html>` tag lost its `lang="en"` attribute, which is an accessibility and SEO regression. Screen readers and search engines use this attribute.

Note: This may be resolved automatically when rebasing onto main (todo 037).

## Findings

- `app/views/layouts/application.html.erb` `<html>` tag missing `lang="en"`
- WCAG 2.1 Level A requires page language to be specified
- Affects both layouts (application and auth)

**Identified by:** Performance Oracle, Data Integrity Guardian

## Proposed Solutions

### Option 1: Add lang="en" back (Recommended)

**Approach:** Add `lang="en"` to `<html>` tag in both layouts. Will likely be resolved during rebase (todo 037).

**Effort:** 5 minutes (if not resolved by rebase)

**Risk:** Low

## Technical Details

**Affected files:**
- `app/views/layouts/application.html.erb`
- `app/views/layouts/auth.html.erb`

## Acceptance Criteria

- [ ] `lang="en"` present on `<html>` tag in both layouts
- [ ] Passes WCAG 2.1 Level A language check

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Performance Oracle, Data Integrity Guardian)
