---
status: pending
priority: p1
issue_id: "155"
tags: [code-review, stripe, webhook, concurrency, data-integrity]
dependencies: []
---

# Stripe webhook handlers lack row lock — TOCTOU race on subscription guard

## Problem Statement
`handle_subscription_updated` and `handle_subscription_deleted` read `subscription.stripe_subscription_id` into memory, check the new tracked-sub guard, then issue `update!`. No `SELECT ... FOR UPDATE` around the read-check-write sequence. Stripe can fire concurrent webhook deliveries for the same customer; two threads can both pass the guard and clobber each other's write, leaving inconsistent state (e.g. `plan: :pro, status: :active, stripe_subscription_id: nil`).

## Findings
- **Source**: Data Integrity Guardian (P1)
- **Location**: `app/controllers/stripe_webhooks_controller.rb:55-73, 76-81`
- Scenario: `customer.subscription.deleted` (sub_A) and `customer.subscription.updated` (sub_A renewal) race
- Thread D reads `stripe_subscription_id=sub_A`, passes guard; Thread U reads same, passes guard
- D commits `stripe_subscription_id=nil, status=canceled`; U then commits `status=active, plan=pro` — paid user without a tracked Stripe sub
- Today's traffic is low enough this is unlikely; it becomes load-bearing as users scale

## Proposed Solutions
**Option A — `with_lock` in each handler** (preferred): Re-fetch + lock inside a transaction, re-check guard under lock, mutate, commit. Minimal change.

**Option B — Wrap the whole `create` action in a transaction with pessimistic lock**: heavier, affects happy path.

## Acceptance Criteria
- [ ] Both `handle_subscription_updated` and `handle_subscription_deleted` run inside `Subscription.transaction { sub.lock!; ... }` (or `with_lock`)
- [ ] Guard checked AFTER the lock
- [ ] Regression test simulates concurrent webhooks (or at minimum documents the lock contract)
