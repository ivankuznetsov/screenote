---
title: StripeWebhookEvent
type: model
source: app/models/stripe_webhook_event.rb
created: 2026-04-21
updated: 2026-04-21
tags: [model, billing, stripe, idempotency]
---

# StripeWebhookEvent

TLDR: Idempotency ledger for Stripe webhook delivery. Records every successfully received Stripe event id so retries (Stripe re-fires on any 5xx) don't re-execute handlers or re-send pro-upgrade mail.

Source: `app/models/stripe_webhook_event.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| stripe_event_id | string | NOT NULL, unique |
| created_at | datetime | |
| updated_at | datetime | |

## Validations

- `stripe_event_id`: presence, uniqueness

## Notes

- Inserted by `StripeWebhooksController` before dispatching to a handler; unique index guarantees at-most-once side effects.
- Added post-incident (2026-04-20 double-billing): Stripe retries had re-triggered handlers.

See also: [[subscription]], [[controllers/web-controllers]]
