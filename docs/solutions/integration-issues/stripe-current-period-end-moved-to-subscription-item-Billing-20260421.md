---
module: Billing
date: 2026-04-21
problem_type: integration_issue
component: payments
symptoms:
  - "NoMethodError: undefined method 'current_period_end' for #<Stripe::Subscription>"
  - "Every customer.subscription.updated webhook returning 500 for 5 weeks (23 Honeybadger occurrences)"
  - "One customer ended up with two active Stripe subscriptions and was double-billed"
root_cause: wrong_api
resolution_type: code_fix
severity: critical
rails_version: 8.1.2
tags: [stripe, webhook, api-versioning, payments, method-missing, hash-access]
---

# Troubleshooting: Stripe API 2026-01-28 moved `current_period_end` off Subscription

## Problem
Stripe API version `2026-01-28` moved `current_period_end` off the Subscription object and onto each `SubscriptionItem`. Our webhook controller read `stripe_sub.current_period_end` via dot access; `Stripe::StripeObject#method_missing` raises `NoMethodError` (not `nil`) on missing keys, so every `customer.subscription.updated` webhook 500'd for 5 weeks. A customer whose sub went past_due resubscribed during this window, creating a second active Stripe subscription. Both renewed monthly — double billing went undetected until the customer noticed.

## Environment
- Module: Billing (Stripe integration)
- Rails Version: 8.1.2
- Stripe Ruby SDK: 18.3.1
- Stripe API Version (live): 2026-01-28.clover
- Affected Component: `app/controllers/stripe_webhooks_controller.rb`
- Date: 2026-04-21

## Symptoms
- Honeybadger fault 128624012: `NoMethodError: undefined method 'current_period_end' for #<Stripe::Subscription:0x...>` at `stripe_webhooks_controller.rb:68`
- First occurrence 2026-03-16 (Stripe-side API cutover), last pre-fix 2026-04-20, 23 total notices
- Customer DB row `current_period_end` stuck at whatever the most recent successful webhook wrote (typically the original checkout value)
- `Stripe::Subscription.list(customer: …)` showed two active subs for the same customer, both billed monthly, our DB tracked only the newer one
- Local DB `stripe_subscription_id` pointed at the duplicate (newer) sub; original sub continued to renew undetected

## What Didn't Work

**Attempted Solution 1:** Check if the webhook was being signed incorrectly or dropped by the proxy.
- **Why it failed:** Signature verification succeeds — `Stripe::Webhook.construct_event` returns a valid event object. The failure was deeper in the handler.

**Attempted Solution 2:** Safe navigation on dot access (`stripe_sub&.current_period_end`).
- **Why it failed:** `&.` only guards against `nil`. `stripe_sub` is a `Stripe::Subscription` object, not nil — `method_missing` still raises.

**Direct solution (after inspecting the captured payload):** The Stripe event payload showed `current_period_end` had moved from the Subscription object to `items.data[0].current_period_end`. Reading Stripe's release notes confirmed this was intentional in API version 2026-01-28.

## Solution

Read `current_period_end` from the first subscription item, and use hash access everywhere to avoid `method_missing` traps on any future field relocations.

**Code changes:**
```ruby
# Before (broken):
attrs = { status: status, current_period_end: Time.at(stripe_sub.current_period_end).utc }
# `stripe_sub.current_period_end` → NoMethodError under Stripe API 2026-01-28

# After (fixed):
attrs = { status: status }
period_end = stripe_period_end(stripe_sub)
attrs[:current_period_end] = Time.at(period_end).utc if period_end

# Helper (lives on Subscription model):
def self.period_end_from_stripe(stripe_sub)
  # StripeObject doesn't implement #dig, hence the explicit chain.
  stripe_sub[:items]&.[](:data)&.first&.[](:current_period_end)
end
```

**Also applied defense-in-depth** — every handler reads StripeObject via `[:key]` hash access rather than dot:
```ruby
# Before:
stripe_sub.customer   # risks NoMethodError on future API shifts
stripe_sub.status
stripe_sub.id

# After:
stripe_sub[:customer]
stripe_sub[:status]
stripe_sub[:id]
```

**Secondary fixes landed in the same deploy:**
- Idempotency: persist `event.id` in a new `stripe_webhook_events` table; short-circuit retries with 200.
- Row lock: wrap each handler in `subscription.with_lock` to close the guard-then-update race.
- Checkout guard: block new Stripe Checkout sessions when the user already has a tracked `stripe_subscription_id`. Closes the past_due → duplicate-sub loophole that caused the double-billing.
- Extracted state transitions onto `Subscription#apply_stripe_update / apply_stripe_deletion / apply_stripe_checkout` so the controller only dispatches.

**One-off reconciliation** (`rake stripe:reconcile_subscriptions`): pages `Stripe::Subscription.list` per customer, flags duplicates for manual review, and syncs stale `current_period_end` values. Dry-run by default; `APPLY=1` commits.

## Why This Works

1. **Root cause:** `Stripe::StripeObject` implements `method_missing` to proxy hash keys as attribute readers, but raises `NoMethodError` when the key isn't present (instead of returning `nil` as a Hash would for `[:missing_key]`). Any time Stripe moves or removes a field in a new API version, code that accesses it via `stripe_sub.field` crashes. Hash access (`stripe_sub[:field]`) returns `nil` for missing keys, making the code resilient.

2. **Why this particular field moved:** Stripe's 2026-01-28 API split per-item billing concerns off the Subscription object. A subscription can have multiple items (price tiers) with different billing cycles, so `current_period_end` logically belongs on the item, not the parent. Existing integrations broke without warning because Stripe versions the API globally but the Ruby SDK ships with a single fallback.

3. **Why the secondary fixes mattered:** The NoMethodError was the proximate cause of the double-billing incident, but the underlying reliability gaps (no idempotency, no row lock, no checkout guard) meant that even once webhooks stopped 500'ing, concurrent events or user retries could still corrupt state. Fixing all four together turned a patch into a proper hardening pass.

## Prevention

- **Always read Stripe payloads via hash access.** Never use dot access on `Stripe::StripeObject` instances unless you own the construction and know the field is guaranteed present. Hash access (`obj[:key]`) returns nil; dot access raises.
- **Pin and monitor the Stripe API version.** Stripe auto-upgrades new accounts. Set a fixed `api_version` in your dashboard or on each `Stripe::…` call, and test against beta versions before they go live.
- **Webhook handlers must be idempotent.** Stripe retries any 5xx; side effects (emails, notifications, analytics) must not fire twice for the same `event.id`. Persist event IDs with a unique index.
- **Every DB mutation triggered by a webhook should run inside `with_lock`.** Stripe fires concurrent events for the same customer under normal load.
- **Guard checkout creation against already-tracked subscriptions.** Don't trust `User#pro?` as a proxy for "has any Stripe sub" — it requires `active? && not-expired`, so a `past_due` customer will slip through.
- **Monitor Honeybadger with a SLO.** A webhook endpoint 500'ing for 5 weeks is a reflection of the monitoring setup, not just the bug. Page on any recurring server error in billing-critical code paths.

## Related Issues

No related issues documented yet (this is the first entry in `docs/solutions/`).

When adding future Stripe-related solutions, link them here:
- (future) Hash-access pattern applied to other Stripe resources (checkout sessions, invoices)
- (future) API version upgrade procedures
