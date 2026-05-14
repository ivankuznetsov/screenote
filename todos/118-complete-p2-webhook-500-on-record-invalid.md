---
status: complete
priority: p2
issue_id: "118"
tags: [code-review, stripe, webhook, pr-11]
dependencies: []
---

# Webhook Returns 500 for `RecordInvalid` — Causes Infinite Stripe Retries

## Problem Statement
The webhook controller rescues both `Stripe::StripeError` and `ActiveRecord::RecordInvalid` with the same `head :internal_server_error`. Returning 500 causes Stripe to retry the webhook up to ~20 times over several days. If `RecordInvalid` is a permanent data issue (bad validation state), every retry fails identically — creating noise in Honeybadger and wasting Stripe retries.

## Findings
- **File**: `app/controllers/stripe_webhooks_controller.rb`, lines 32-34
- Identified by: Data Integrity Guardian, Kieran Rails Reviewer

## Proposed Solutions

### Option A: Separate rescue clauses (Recommended)
```ruby
rescue ActiveRecord::RecordInvalid => e
  Honeybadger.notify(e, context: { event_type: event&.type, event_id: event&.id })
  head :ok  # Stop retries for permanent validation failures
rescue Stripe::StripeError => e
  Honeybadger.notify(e, context: { event_type: event&.type, event_id: event&.id })
  head :internal_server_error  # Retry transient Stripe errors
end
```
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] `RecordInvalid` returns 200 (stops retries)
- [ ] `StripeError` returns 500 (triggers retries)
- [ ] Both still notify Honeybadger
- [ ] Tests updated for both scenarios

## Work Log
- 2026-02-16: Created from PR #11 code review
