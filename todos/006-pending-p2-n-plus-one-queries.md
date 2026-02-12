---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, performance]
dependencies: []
---

# N+1 Queries in Screenshot Grid and MCP Tools

## Problem Statement
The screenshot grid partial fires 2 COUNT queries per screenshot (open annotations + total annotations). The same pattern exists in ListScreenshotsTool. With 20 screenshots, this generates 40+ extra queries. Also missing eager loading for Active Storage attachments.

## Findings
- `app/views/screenshots/_screenshot_grid.html.erb:15-17`: `screenshot.annotations.open.count` and `screenshot.annotations.count` in loop
- `app/tools/list_screenshots_tool.rb:24-25`: Same N+1 COUNT pattern
- `app/controllers/screenshots_controller.rb:8`: No `with_attached_image` or counter cache
- `app/views/projects/show.html.erb:17`: Inline query bypasses controller eager loading
- Agents: performance-oracle (CRITICAL-1, CRITICAL-2), dhh-rails-reviewer, pattern-recognition, simplicity-reviewer

## Proposed Solutions

### Option A: Counter cache columns (Recommended)
Add `annotations_count` and `open_annotations_count` counter cache columns to screenshots table. Use `counter_cache: true` on belongs_to or manual increment.
- Effort: Medium
- Risk: Low

### Option B: SQL subquery with left_joins
Use `.left_joins(:annotations).select("screenshots.*, COUNT(annotations.id) AS annotations_count").group("screenshots.id")`
- Effort: Small
- Risk: Low

## Acceptance Criteria
- [ ] Screenshot grid does not fire per-row COUNT queries
- [ ] ListScreenshotsTool uses preloaded counts
- [ ] Controller uses `with_attached_image` for eager loading
- [ ] Projects/show passes screenshots from controller, not inline query

## Work Log
- 2026-02-12: Created from code review (6 agents flagged this)
