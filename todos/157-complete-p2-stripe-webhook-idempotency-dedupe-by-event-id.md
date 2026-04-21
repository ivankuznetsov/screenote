---
status: pending
priority: p2
issue_id: "157"
tags: [code-review, stripe, webhook, reliability, idempotency]
dependencies: []
---

# Stripe webhook processing is not idempotent — retries can double-send mail

## Problem Statement
Stripe retries on any 5xx response. The controller logs `event.id` at line 18 but never persists it. `update!` itself is naturally idempotent (same target state), but the mailer side-effect at line 77 (`AdminMailer.new_pro_subscriber`) is NOT idempotent: if a retried `customer.subscription.updated` crosses the `!was_active_pro && active_pro?` edge twice (e.g. prior run partially failed after `update!` but before Stripe got a 200), a duplicate email is sent.

## Findings
- **Source**: Architecture Strategist (P1 in their report, consolidated as P2 here)
- **Location**: `app/controllers/stripe_webhooks_controller.rb:18, 73, 77`
- No `processed_stripe_events` table / unique index
- Retries are natural and expected

## Proposed Solutions
**Option A — dedicated table + early short-circuit**:
```ruby
create_table :stripe_webhook_events do |t|
  t.string :stripe_event_id, null: false, index: { unique: true }
  t.timestamps
end

# Controller
return head :ok unless StripeWebhookEvent.create(stripe_event_id: event.id) rescue head :ok
```

**Option B — mark on `Subscription`**: add `last_processed_stripe_event_id` column. Simpler but doesn't work for events that span multiple subscriptions.

## Acceptance Criteria
- [ ] Replayed events with the same `event.id` are short-circuited with 200 and do not re-trigger `update!` or mailers
- [ ] Regression test: post the same event twice, assert only one email enqueued
