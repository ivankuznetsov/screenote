---
status: complete
priority: p2
issue_id: "121"
tags: [code-review, performance, stripe, webhook, pr-11]
dependencies: []
---

# Synchronous `Stripe::Subscription.retrieve` in Webhook Handler

## Problem Statement
The `handle_checkout_completed` webhook handler makes a synchronous HTTP call to `Stripe::Subscription.retrieve` during webhook processing. This adds 200-500ms latency and creates a circular dependency: Stripe sends webhook, server calls back to Stripe. During Stripe outages, this causes a retry storm.

## Findings
- **File**: `app/controllers/stripe_webhooks_controller.rb`, line 44
- Identified by: Performance Oracle (CRITICAL)
- The `checkout.session.completed` event data is sufficient to set `stripe_subscription_id` and `plan: :pro`
- The subsequent `customer.subscription.updated` webhook provides the detailed status

## Proposed Solutions

### Option A: Skip retrieve, set incomplete status (Recommended)
```ruby
def handle_checkout_completed(session)
  subscription = find_subscription(session.customer, "checkout.session.completed")
  return unless subscription
  return unless session.subscription

  subscription.update!(
    stripe_subscription_id: session.subscription,
    plan: :pro,
    status: :incomplete  # Updated to :active by customer.subscription.updated webhook
  )
end
```
- **Pros**: Eliminates Stripe API call, no circular dependency, faster
- **Cons**: Brief window where status is :incomplete until next webhook
- **Effort**: Small
- **Risk**: Low

### Option B: Use `expand` parameter on checkout session creation
Pre-expand subscription data when creating the checkout session so it's included in the webhook payload.
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] No synchronous Stripe API call in webhook handler
- [ ] Subscription correctly transitions to pro
- [ ] Tests updated

## Work Log
- 2026-02-16: Created from PR #11 performance review
