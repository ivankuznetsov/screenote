---
title: Subscription
type: model
source: app/models/subscription.rb
created: 2026-04-10
updated: 2026-04-10
tags: [model, billing, stripe, subscription]
---

# Subscription

TLDR: Tracks Stripe subscription state per user. Two plans: free (1 project, 1 member) and pro ($10/month, unlimited). One subscription per user. State is webhook-driven from Stripe.

Source: `app/models/subscription.rb`

## Columns

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| user_id | integer | NOT NULL, FK to users, unique |
| stripe_customer_id | string | NOT NULL, unique |
| stripe_subscription_id | string | Unique (nullable for free/incomplete) |
| plan | integer | Enum: free(0), pro(1). Default: free |
| status | integer | Enum: incomplete(0), active(1), past_due(2), canceled(3). Default: incomplete |
| current_period_end | datetime | When the current billing period ends |
| created_at | datetime | |
| updated_at | datetime | |

## Associations

| Association | Type | Target |
|-------------|------|--------|
| user | belongs_to | [[user]] |

## Enums

- `plan`: `{ free: 0, pro: 1 }`
- `status`: `{ incomplete: 0, active: 1, past_due: 2, canceled: 3 }`

## Validations

- `stripe_customer_id`: presence, uniqueness
- `user_id`: uniqueness (one subscription per user)
- `stripe_subscription_id`: presence, if pro? and active?
- `current_period_end`: presence, if pro? and active?

## Constants

- `FREE_PROJECT_LIMIT = 1`
- `FREE_MEMBER_LIMIT = 1`
- `PRO_PRICE_CENTS = 1000` ($10.00)

## Key Methods

- `active_pro?` -- Returns true if plan is pro, status is active, and current_period_end is in the future

## Notes

- Subscription records are created lazily when a user first clicks "checkout" (not at registration).
- State transitions are driven by Stripe webhooks handled in `StripeWebhooksController`: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`.
- The `incomplete` status is the initial state before Stripe confirms payment.

See also: [[user]], [[controllers/web-controllers]]
