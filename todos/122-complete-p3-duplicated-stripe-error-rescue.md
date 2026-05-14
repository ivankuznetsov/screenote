---
status: complete
priority: p3
issue_id: "122"
tags: [code-review, rails, dry, pr-11]
dependencies: []
---

# Duplicated Stripe Error Rescue in `SubscriptionsController`

## Problem Statement
The identical `rescue Stripe::StripeError` block with Honeybadger notification and redirect appears in both `checkout` and `portal` actions. Could be consolidated with `rescue_from` at the controller level.

## Findings
- **File**: `app/controllers/subscriptions_controller.rb`, lines 25-27 and 43-45
- Identified by: Pattern Recognition

## Proposed Solutions

### Option A: Use `rescue_from` (Recommended)
```ruby
rescue_from Stripe::StripeError do |e|
  Honeybadger.notify(e)
  redirect_to subscription_path, alert: "We couldn't connect to our payment provider. Please try again shortly."
end
```
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Single rescue handler for Stripe errors
- [ ] Both actions still show friendly error message

## Work Log
- 2026-02-16: Created from PR #11 code review
