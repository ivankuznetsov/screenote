---
status: pending
priority: p2
issue_id: "029"
tags: [code-review, dry, rails]
dependencies: []
---

# Extract Shared `<head>` Partial Across 3 Layouts

## Problem Statement
All three layouts (application, auth, landing) repeat ~15 lines of identical `<head>` boilerplate: meta tags, CSRF, CSP, favicon links, stylesheet, importmap. The landing and auth layouts are also missing Honeybadger JS monitoring, meaning JS errors on public pages go unreported in production. Additionally, `application.html.erb` lacks `lang="en"` while the other two have it.

## Findings
- Shared boilerplate: meta viewport, apple-mobile-web-app-capable, application-name, csrf_meta_tags, csp_meta_tag, yield :head, icons, stylesheet_link_tag, javascript_importmap_tags
- Landing and auth layouts missing Honeybadger JS (violates CLAUDE.md: "Send all errors to Honeybadger")
- `application.html.erb` missing `lang="en"` (accessibility inconsistency)
- Agents: architecture-strategist, dhh-rails-reviewer, pattern-recognition-specialist, code-simplicity-reviewer

## Proposed Solutions

### Option A: Extract `_head.html.erb` partial (Recommended)
Create `app/views/layouts/_head.html.erb` with shared meta tags, icons, and Honeybadger JS. Render from all three layouts.
- Pros: DRY, consistent Honeybadger monitoring, single place for changes
- Cons: Minor refactor
- Effort: Small
- Risk: Low

## Technical Details
- **Affected files:** `app/views/layouts/_head.html.erb` (new), all 3 layout files
- **PR:** #6

## Acceptance Criteria
- [ ] Shared `_head.html.erb` partial exists
- [ ] All 3 layouts render the shared partial
- [ ] Honeybadger JS present on all pages in production
- [ ] `lang="en"` on all `<html>` tags

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | DRY layouts prevent drift |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
