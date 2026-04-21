---
status: pending
priority: p2
issue_id: "159"
tags: [code-review, stripe, webhook, readability]
dependencies: []
---

# Replace `&.[](:key)&.first&.[](:key)` chain with `.dig(:key, 0, :key)`

## Problem Statement
`stripe_period_end` uses `stripe_sub[:items]&.[](:data)&.first&.[](:current_period_end)` — a cryptic safe-nav chain. `Stripe::StripeObject` responds to `#dig` (since stripe-ruby 5.x) which reads left-to-right in one line.

## Findings
- **Source**: Kieran Rails Reviewer, Code Simplicity Reviewer (both flagged)
- **Location**: `app/controllers/stripe_webhooks_controller.rb:98`
- Current: `stripe_sub[:items]&.[](:data)&.first&.[](:current_period_end)`
- Preferred: `stripe_sub.dig(:items, :data, 0, :current_period_end)`

## Acceptance Criteria
- [ ] `stripe_period_end` uses `.dig`
- [ ] Tests still pass (incl. the "tolerates empty items list" regression test)
- [ ] Verify `Stripe::ListObject#dig` works when `:data` lookup traverses a ListObject (may need `stripe_sub.dig(:items, :data)&.first&.dig(:current_period_end)` if ListObject#dig is missing)
