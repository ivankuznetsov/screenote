---
status: pending
priority: p2
issue_id: "158"
tags: [code-review, stripe, webhook, data-integrity, backfill]
dependencies: []
---

# Reconcile stale current_period_end and audit duplicate Stripe subs

## Problem Statement
Between the Stripe API 2026-01-28 change and the 2026-04-20 fix, every `customer.subscription.updated` raised `NoMethodError` before `update!` ran. Affected users may still have a stale `current_period_end` (whatever the last successful webhook wrote — typically the initial checkout value). `Subscription#active_pro?` depends on `current_period_end > Time.current`, so paid users will silently flip to non-pro once that stale date passes. Additionally, Ivan's case (two active Stripe subs for the same customer) may not be unique — need an audit.

## Findings
- **Source**: Data Integrity Guardian
- **Incident evidence**: Honeybadger fault 128624012 logged 23 occurrences from 2026-03-16 to 2026-04-20; only ivan@ikuznetsov.com verified so far
- Ivan's DB row: `current_period_end=2026-03-18` (a month stale) before the fix

## Proposed Solutions
**One-off Rake task `stripe:reconcile_subscriptions`:**
1. For each `Subscription` with `stripe_customer_id`:
   - Fetch `Stripe::Subscription.list(customer:, status: "all")`
   - Flag customers with >1 non-canceled Stripe sub
   - If single active sub: update local row (`stripe_subscription_id`, `current_period_end`, `status`, `plan`) to match Stripe's truth
2. Output a report for manual review of duplicates

## Acceptance Criteria
- [ ] Rake task runs dry-run mode by default (prints diffs only)
- [ ] `--apply` flag commits the reconciliation
- [ ] Log report of customers with duplicate active Stripe subs for manual handling
- [ ] Run against prod (one-off), then delete or mark dormant
