---
status: pending
priority: p3
issue_id: "174"
tags: [code-review, security, idor, pre-existing]
dependencies: []
---

# Pre-existing: `Screenshot.find(params[:id])` not scoped to current user

## Problem Statement
`ScreenshotsController#set_screenshot` does `Screenshot.find(params[:id])` then relies on `Current.user.projects.find(@page.project_id)` to raise `RecordNotFound` for non-members. The authorization works — but the flow is "read row, THEN check ownership" instead of "scope the query to the user." This is pre-existing, not introduced by PR-3 — but the new viewport route increased the surface slightly.

## Findings
- **Source**: Security Sentinel review of PR #30 (flagged as pre-existing, not a PR-3 regression)
- **Location**: `app/controllers/screenshots_controller.rb:72-75`

## Proposed Solution
Scope the initial lookup through the user's projects:
```ruby
def set_screenshot
  @screenshot = Screenshot.joins(page: :project).where(projects: { user_id: Current.user.id }).find(params[:id])
  @page = @screenshot.page
  @project = @page.project
rescue ActiveRecord::RecordNotFound
  head :not_found
end
```
Or use a pundit-style policy object if the codebase moves that direction.

## Acceptance Criteria
- [ ] `set_screenshot` filters by `Current.user` before the find
- [ ] Tests cover the "other user's screenshot returns 404" path (already exists)
