---
status: pending
priority: p2
issue_id: "161"
tags: [code-review, stripe, webhook, reliability]
dependencies: []
---

# `handle_checkout_completed` silently fakes `current_period_end` with 30-day fallback

## Problem Statement
When `checkout.session.completed` fires without a prior `customer.subscription.updated`, the controller writes `current_period_end: subscription.current_period_end || 30.days.from_now`. That fallback is a guess — the real Stripe subscription's period may be different (annual, trialing, prorated, etc.). `Subscription#active_pro?` treats this value as truth, so a user could lose access early or keep access past their real expiry.

## Findings
- **Source**: Architecture Strategist
- **Location**: `app/controllers/stripe_webhooks_controller.rb:47-52`
- Depends on webhook ordering (updated-before-checkout) to have a real value — fragile
- Fix: `Stripe::Subscription.retrieve(session.subscription)` and read `items.data[0].current_period_end`

## Proposed Solutions
Fetch the subscription synchronously in `handle_checkout_completed`:
```ruby
def handle_checkout_completed(session)
  subscription = find_subscription(session.customer, "checkout.session.completed")
  return head(:service_unavailable) unless subscription
  return unless session.subscription

  stripe_sub = Stripe::Subscription.retrieve(session.subscription)
  period_end = stripe_period_end(stripe_sub)

  subscription.update!(
    stripe_subscription_id: session.subscription,
    plan: :pro,
    status: :active,
    current_period_end: period_end ? Time.at(period_end).utc : 30.days.from_now
  )
end
```

## Acceptance Criteria
- [ ] `handle_checkout_completed` reads the real period_end from Stripe
- [ ] 30-day fallback only fires when Stripe API is genuinely unreachable (retries take care of that; still safe)
- [ ] Test mocks `Stripe::Subscription.retrieve`
