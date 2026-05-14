---
status: complete
priority: p2
issue_id: "117"
tags: [code-review, security, stripe, race-condition, pr-11]
dependencies: []
---

# Race Condition in `find_or_create_subscription` Leaks Orphaned Stripe Customers

## Problem Statement
When two concurrent requests hit `checkout` for the same user, both call `Stripe::Customer.create` before attempting the database insert. The unique index on `user_id` catches the race and the rescue block correctly returns the winner's subscription. However, the loser's Stripe Customer object (`cus_BBB`) is created but never linked — it's orphaned in Stripe forever.

## Findings
- **File**: `app/controllers/subscriptions_controller.rb`, lines 50-63
- Identified by: Data Integrity Guardian (Medium), Security Sentinel (HIGH), Performance Oracle
- External side-effect (Stripe API call) happens before the database guard
- Orphaned customers accumulate over time

## Proposed Solutions

### Option A: Add `with_lock` before Stripe call (Recommended)
```ruby
def find_or_create_subscription
  Current.user.with_lock do
    Current.user.subscription || create_subscription_with_stripe_customer
  end
end
```
- **Pros**: Prevents orphaned Stripe customers entirely
- **Cons**: Holds DB row lock during Stripe API call (~300ms)
- **Effort**: Small
- **Risk**: Low

### Option B: Keep current pattern + periodic cleanup job
- **Pros**: No lock contention
- **Cons**: Orphaned customers exist until cleanup runs
- **Effort**: Medium
- **Risk**: Low

## Acceptance Criteria
- [ ] Concurrent checkout requests do not create orphaned Stripe customers
- [ ] Only one Stripe customer per user
- [ ] Existing race condition test still passes

## Work Log
- 2026-02-16: Created from PR #11 code review
