---
status: complete
priority: p1
issue_id: "110"
tags: [code-review, testing, stripe, pr-11]
dependencies: []
---

# Missing Test Coverage for `checkout` and `portal` Controller Actions

## Problem Statement
`SubscriptionsController` has three actions: `show`, `checkout`, and `portal`. Only `show` is tested. The `checkout` and `portal` actions contain critical business logic (pro guard, Stripe session creation, race condition handling, error rescue) with zero test coverage. These are the two most important actions in the billing flow.

## Findings
- **File**: `test/controllers/subscriptions_controller_test.rb` — only tests `#show`
- Identified by: Kieran Rails Reviewer, Pattern Recognition
- `checkout` contains: pro-user redirect guard, `find_or_create_subscription` with race handling, Stripe API call, error rescue
- `portal` contains: nil-subscription guard, Stripe API call, error rescue
- The race condition in `create_subscription_with_stripe_customer` is completely untested

## Proposed Solutions

### Option A: Add controller tests with Stripe stubs (Recommended)
Test at minimum:
1. `checkout` redirects pro users back with notice
2. `checkout` for free user (stub `Stripe::Checkout::Session.create`, assert redirect)
3. `checkout` when Stripe raises `StripeError` returns friendly alert
4. `portal` with no subscription returns alert
5. `portal` with subscription (stub portal session, assert redirect)
- **Pros**: Full coverage of business logic paths
- **Cons**: Requires Stripe method stubbing
- **Effort**: Medium
- **Risk**: Low

## Technical Details
- Affected files: `test/controllers/subscriptions_controller_test.rb`
- Controller: `app/controllers/subscriptions_controller.rb`

## Acceptance Criteria
- [ ] Test: pro user hitting checkout is redirected with notice
- [ ] Test: free user checkout creates session and redirects
- [ ] Test: checkout Stripe error shows friendly message
- [ ] Test: portal without subscription shows alert
- [ ] Test: portal with subscription redirects to Stripe portal
- [ ] All tests pass

## Work Log
- 2026-02-16: Created from PR #11 code review
