---
status: complete
priority: p1
issue_id: "112"
tags: [code-review, security, stripe, billing, pr-11]
dependencies: []
---

# Webhook `find_subscription` Returns 200 When Not Found — Silently Loses Upgrades

## Problem Statement
When `find_subscription` cannot find a local subscription record for a Stripe customer ID, it logs to Honeybadger but the calling handler returns early. The outer `create` action then falls through to `head :ok` (line 31). Returning 200 tells Stripe the event was processed successfully, so Stripe will NOT retry. If the webhook fires before the Subscription record is committed (race with checkout), the upgrade is **permanently lost** — the user paid but never gets Pro.

## Findings
- **File**: `app/controllers/stripe_webhooks_controller.rb`, lines 77-86 and line 31
- Identified by: Security Sentinel (LOW severity, but upgraded to P1 due to revenue impact)
- `find_subscription` returns `nil`, handler returns early, falls through to `head :ok`
- Stripe will not retry a 200 response
- Race window: checkout creates Stripe customer → webhook fires → local record not yet committed

## Proposed Solutions

### Option A: Return retryable status when subscription not found (Recommended)
```ruby
def find_subscription(stripe_customer_id, event_type)
  subscription = Subscription.find_by(stripe_customer_id: stripe_customer_id)
  unless subscription
    Honeybadger.notify("Stripe webhook: no subscription found", context: {
      stripe_customer_id: stripe_customer_id,
      event_type: event_type
    })
  end
  subscription
end
```
And in each handler, when subscription is nil, render a retryable status:
```ruby
def handle_checkout_completed(session)
  subscription = find_subscription(session.customer, "checkout.session.completed")
  unless subscription
    head :service_unavailable  # Stripe will retry
    return
  end
  # ...
end
```
- **Pros**: Stripe retries until subscription record exists
- **Cons**: Need to handle `head` already sent in caller; slightly more complex flow
- **Effort**: Small
- **Risk**: Low

### Option B: Use a short delay/retry approach
Raise an exception when subscription not found, caught by outer rescue returning 500:
```ruby
raise ActiveRecord::RecordNotFound, "No subscription for #{stripe_customer_id}"
```
- **Pros**: Simple, Stripe retries automatically on 500
- **Cons**: Generates Honeybadger noise for legitimate race conditions
- **Effort**: Small
- **Risk**: Low

## Technical Details
- Affected files: `app/controllers/stripe_webhooks_controller.rb`
- Tests to update: `test/controllers/stripe_webhooks_controller_test.rb`

## Acceptance Criteria
- [ ] When subscription not found, webhook returns non-200 status
- [ ] Stripe retries the webhook (verify with test)
- [ ] Honeybadger notification still fires for debugging
- [ ] Existing "not found" test updated to expect retryable status

## Work Log
- 2026-02-16: Created from PR #11 security review
