---
status: complete
priority: p1
issue_id: "111"
tags: [code-review, security, stripe, billing, pr-11]
dependencies: []
---

# No `current_period_end` Expiry Check — Indefinite Pro Access If Webhook Fails

## Problem Statement
`Subscription#active_pro?` only checks `pro? && status_active?` without verifying that `current_period_end` is in the future. If the `customer.subscription.updated` or `customer.subscription.deleted` webhook fails to deliver (network outage, bug, Stripe incident), the subscription record stays `plan: pro, status: active` indefinitely — even after the billing period expired in Stripe. This is a **revenue leakage** vulnerability.

## Findings
- **File**: `app/models/subscription.rb`, line 18-20
- Identified by: Security Sentinel (HIGH severity)
- `active_pro?` does not check `current_period_end > Time.current`
- If Stripe fails to deliver deletion/update webhooks, user retains Pro forever
- No reconciliation job exists to catch drift between Stripe and local state

## Proposed Solutions

### Option A: Add time check to `active_pro?` (Recommended)
```ruby
def active_pro?
  pro? && status_active? && current_period_end.present? && current_period_end > Time.current
end
```
- **Pros**: Immediate protection, simple, no external dependencies
- **Cons**: Users lose Pro the instant period ends (no grace period)
- **Effort**: Small
- **Risk**: Low

### Option B: Add time check + periodic reconciliation job
Same as A, plus a daily background job that syncs subscription status from Stripe:
```ruby
Subscription.where(plan: :pro, status: :active)
  .where("current_period_end < ?", Time.current)
  .find_each { |sub| StripeReconciliationService.sync(sub) }
```
- **Pros**: Belt-and-suspenders, catches all drift
- **Cons**: More complex, requires Stripe API calls
- **Effort**: Medium
- **Risk**: Low

## Technical Details
- Affected files: `app/models/subscription.rb`
- Tests to update: `test/models/subscription_test.rb`

## Acceptance Criteria
- [ ] `active_pro?` returns false when `current_period_end` is in the past
- [ ] `pro?` returns false when period has expired
- [ ] Tests cover expired subscription scenario
- [ ] Existing tests still pass

## Work Log
- 2026-02-16: Created from PR #11 security review
