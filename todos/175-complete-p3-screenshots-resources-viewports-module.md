---
status: complete
priority: p3
issue_id: "175"
tags: [code-review, rails, routes, polish, wontfix]
dependencies: []
---

## Resolution — wontfix
Reviewed during PR-3 review cycle; decided the member route is fine:

- `get "viewports/:viewport" -> "screenshots#show"` IS a Rails convention
  (single endpoint accepting a path param), just not the RESTful-nested
  one. A dedicated `Screenshots::ViewportsController` would duplicate
  show-setup code or require inheritance gymnastics.
- No security, correctness, or user-facing concern — pure style preference.

Keeping the member route.


# Consider `resources :viewports` + nested controller instead of member route

## Problem Statement
PR-3 added `/screenshots/:id/viewports/:viewport` as a member route that dispatches back to `screenshots#show`. Kieran flagged this as "not really a member route, it's a pseudo-nested resource." A cleaner Rails shape would be:

```ruby
resources :screenshots, only: %i[show edit update destroy] do
  resources :viewports, only: :show, controller: "screenshot_viewports"
end
```

with a dedicated `Screenshots::ViewportsController#show` that sets `@active_viewport` from `params[:id]` and renders the shared `screenshots/show` template.

## Findings
- **Source**: Kieran Rails Reviewer P2 on PR #30
- **Location**: `config/routes.rb:29-32`
- Current shape works fine; the simplification argument is that "four controllers with simple actions" beats "three with complex conditional dispatching" (per CLAUDE.md).

## Acceptance Criteria
- [ ] `Screenshots::ViewportsController` exists and handles the viewport-specific show
- [ ] Both `/screenshots/:id` and `/screenshots/:id/viewports/:viewport` render the same template via a shared setup path
- [ ] The regex constraint on viewport is removed in favor of controller-level allowlist (defense in depth already in place)
