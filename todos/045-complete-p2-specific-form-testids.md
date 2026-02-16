---
status: pending
priority: p2
issue_id: "045"
tags: [code-review, tests, data-testid]
dependencies: []
---

# Use specific data-testid values for project and screenshot forms

## Problem Statement

Both project and screenshot forms use generic `data-testid="form"` and `data-testid="form-errors"`. If a page ever renders both form types, selectors would be ambiguous.

## Findings

- `app/views/projects/_form.html.erb` uses `data-testid="form"`
- `app/views/screenshots/_form.html.erb` uses `data-testid="form"`
- POM `FORM` selector in projects_page.rb targets `[data-testid="form"]`
- Currently not a runtime problem (forms are on separate pages), but poor practice

**Identified by:** Kieran Rails Reviewer, Agent-Native Reviewer, Pattern Recognition

## Proposed Solutions

### Option 1: Namespace testids (Recommended)

**Approach:** Use `data-testid="project-form"` and `data-testid="screenshot-form"`, similarly for errors.

**Effort:** 30 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `app/views/projects/_form.html.erb`
- `app/views/screenshots/_form.html.erb`
- `test/system/pages/projects_page.rb`
- `test/system/pages/screenshots_page.rb`

## Acceptance Criteria

- [ ] Forms have unique data-testid values
- [ ] POM selectors updated
- [ ] All tests still pass

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Kieran Rails Reviewer, Pattern Recognition)
