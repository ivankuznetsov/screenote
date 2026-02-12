---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, architecture, rails]
dependencies: []
---

# Move Annotation Status Filtering from View to Controller

## Problem Statement
`screenshots/show.html.erb:39` performs ActiveRecord `.where()` filtering directly in the ERB template, violating the convention of keeping query logic in controllers.

## Findings
- `app/views/screenshots/show.html.erb:39`: `params[:status].in?(%w[open resolved]) ? @annotations.where(status: params[:status]) : @annotations`
- Controller at `screenshots_controller.rb:12` loads all annotations but doesn't handle status filter
- Agents: performance-oracle (OPT-4), dhh-rails-reviewer (Finding 4), pattern-recognition, architecture-strategist, simplicity-reviewer

## Proposed Solutions

### Option A: Move to controller (Recommended)
```ruby
def show
  @annotations = @screenshot.annotations.includes(:user).order(:created_at)
  @annotations = @annotations.where(status: params[:status]) if params[:status].in?(%w[open resolved])
end
```
- Effort: Small | Risk: Low

## Acceptance Criteria
- [ ] No ActiveRecord queries in view templates
- [ ] Status filtering happens in ScreenshotsController#show
- [ ] View simply iterates @annotations

## Work Log
- 2026-02-12: Created from code review (5 agents flagged this)
