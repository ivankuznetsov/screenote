---
status: pending
priority: p3
issue_id: "163"
tags: [code-review, stripe, webhook, performance, polish]
dependencies: []
---

# `ENV.fetch("STRIPE_WEBHOOK_SECRET")` called on every request

## Problem Statement
Line 11 re-reads the env var on every webhook. Cheap, but pointless — the value is fixed at boot.

## Findings
- **Source**: DHH Rails Reviewer
- **Location**: `app/controllers/stripe_webhooks_controller.rb:11`

## Proposed Solutions
Hoist to a constant or class attribute:
```ruby
class StripeWebhooksController < ActionController::Base
  WEBHOOK_SECRET = ENV.fetch("STRIPE_WEBHOOK_SECRET")
  ...
  event = Stripe::Webhook.construct_event(payload, sig_header, WEBHOOK_SECRET)
end
```

Note: must be consistent with `config/initializers/stripe.rb` pattern (production fails-fast on missing env vars; test uses `ENV["STRIPE_WEBHOOK_SECRET"] = ...` in setup — a constant at class-load time would break that test pattern). Keep as-is if it complicates testing.

## Acceptance Criteria
- [ ] ENV var read at boot, not per request, OR this todo closed as "not worth it" due to test coupling
