---
status: pending
priority: p2
issue_id: "162"
tags: [code-review, stripe, billing, data-integrity]
dependencies: []
---

# Checkout doesn't prevent double-subscription for already-active-pro users

## Problem Statement
`SubscriptionsController#checkout` lets any signed-in user create a new Stripe Checkout session, regardless of whether they already have an active Stripe subscription. This is how Ivan ended up with two active subs charged $10/mo each (ref: 2026-04-20 incident). The new webhook guard prevents corruption *after* the fact, but does nothing to stop the duplicate from being created in the first place.

## Findings
- **Source**: Architecture Strategist, Data Integrity Guardian
- **Location**: `app/controllers/subscriptions_controller.rb` (checkout action)
- `subscriptions` table has unique index on `user_id`, not on `stripe_subscription_id`
- Stripe permits multiple simultaneous subs per customer

## Proposed Solutions
Gate checkout creation in the controller:
```ruby
def checkout
  return redirect_to billing_path, alert: "You're already subscribed" if Current.user.subscription&.active_pro?
  # ... existing checkout session creation
end
```

Additionally consider: on manual cancellation, cancel the Stripe sub (not just local state) so the customer can cleanly re-subscribe.

## Acceptance Criteria
- [ ] Attempting to create a second checkout session while already active_pro is blocked with a user-friendly redirect
- [ ] Integration test: user with active pro cannot reach Stripe Checkout
- [ ] Manual cancel flow (if any) terminates Stripe sub before permitting new checkout
