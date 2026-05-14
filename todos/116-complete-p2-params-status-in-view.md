---
status: complete
priority: p2
issue_id: "116"
tags: [code-review, rails, views, pr-11]
dependencies: []
---

# `params[:status]` Accessed Directly in View

## Problem Statement
The subscription show view reads `params[:status]` directly to display checkout success/cancel messages. Accessing `params` in views is a Rails anti-pattern — the controller should set instance variables.

## Findings
- **File**: `app/views/subscriptions/show.html.erb`, line 7
- Identified by: Kieran Rails Reviewer

## Proposed Solutions

### Option A: Set instance variable in controller (Recommended)
```ruby
# subscriptions_controller.rb
def show
  @subscription = Current.user.subscription
  @checkout_status = params[:status]
end
```
```erb
<% if @checkout_status == "success" %>
```
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] `params[:status]` replaced with `@checkout_status` in view
- [ ] Controller sets `@checkout_status`
- [ ] Checkout success/cancel messages still display correctly

## Work Log
- 2026-02-16: Created from PR #11 code review
