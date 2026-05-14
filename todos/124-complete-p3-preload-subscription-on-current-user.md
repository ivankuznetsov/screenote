---
status: complete
priority: p3
issue_id: "124"
tags: [code-review, performance, rails, pr-11]
dependencies: []
---

# Preload Subscription on `Current.user` to Eliminate Extra Query Per Request

## Problem Statement
The auth gem loads `Current.user` via `Session.includes(:user)` but does NOT eager-load the `subscription` association. Every authenticated page now triggers an additional `SELECT * FROM subscriptions WHERE user_id = ?` query due to `pro?` calls in views/controllers. This is +1 query on every authenticated page load globally.

## Findings
- Identified by: Performance Oracle (CRITICAL-1)
- `pro?` is called in views: 5x on `subscriptions/show`, 3x on `projects/index`, 1x on `project_memberships/index`
- ActiveRecord caches after first load within request, so it's 1 extra query per request (not per call)
- At scale, this is unnecessary overhead on every page

## Proposed Solutions

### Option A: Preload in `ApplicationController` `before_action`
```ruby
before_action :preload_subscription

def preload_subscription
  return unless Current.user
  Current.user.subscription # triggers load, cached for rest of request
end
```
- **Effort**: Small
- **Risk**: Low

### Option B: Use controller instance variables
Set `@is_pro = Current.user.pro?` in controllers that need it, use in views.
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] No extra subscription query per request (or explicitly preloaded once)
- [ ] Views use preloaded data

## Work Log
- 2026-02-16: Created from PR #11 performance review
