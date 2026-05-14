---
status: complete
priority: p1
issue_id: "109"
tags: [code-review, testing, stripe, pr-11]
dependencies: []
---

# Webhook Test Assertions Inside `ensure` Block Silently Pass

## Problem Statement
In `test/controllers/stripe_webhooks_controller_test.rb`, the `checkout.session.completed` test places all assertions after the `ensure` keyword. Assertions in `ensure` blocks execute regardless of whether the test body raised an exception — meaning the test will always pass even if `post_webhook` fails. This is a silent correctness bug that undermines the entire webhook test suite.

## Findings
- **File**: `test/controllers/stripe_webhooks_controller_test.rb`, lines 30-53
- Identified by: Kieran Rails Reviewer, Architecture Strategist, Pattern Recognition
- The `ensure` block correctly restores `Stripe::Subscription.retrieve`, but the assertions that follow will run even if an exception occurred, producing false passes or misleading failures
- The test currently passes, but it would also pass if the webhook handler was completely broken

## Proposed Solutions

### Option A: Move assertions before `ensure` with `begin/ensure` (Recommended)
```ruby
test "checkout.session.completed upgrades subscription to pro" do
  # setup...
  Stripe::Subscription.define_singleton_method(:retrieve) { |_id| stripe_sub_mock }
  begin
    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.pro?, "Subscription should be upgraded to pro"
    assert @subscription.status_active?, "Subscription status should be active"
    assert_equal "sub_new_test_123", @subscription.stripe_subscription_id
    assert_not_nil @subscription.current_period_end, "current_period_end should be set"
  ensure
    Stripe::Subscription.define_singleton_method(:retrieve, original_method)
  end
end
```
- **Pros**: Clean separation of assertions and cleanup
- **Cons**: None
- **Effort**: Small
- **Risk**: Low

## Technical Details
- Affected files: `test/controllers/stripe_webhooks_controller_test.rb`

## Acceptance Criteria
- [ ] Assertions are placed inside `begin` block, before `ensure`
- [ ] Only method restoration remains in `ensure`
- [ ] Test fails correctly when webhook handler is broken (verify by temporarily breaking handler)
- [ ] All webhook tests still pass

## Work Log
- 2026-02-16: Created from PR #11 code review — flagged by 3 agents
