---
status: pending
priority: p1
issue_id: "154"
tags: [code-review, stripe, webhook, reliability]
dependencies: []
---

# Stripe webhook mixes dot-access and hash-access on StripeObject

## Problem Statement
The webhook controller uses `stripe_sub.customer` / `stripe_sub.status` (dot access) alongside the newly-introduced `stripe_sub[:id]` / `stripe_sub[:items]` (hash access). The whole justification for the hash idiom was that `StripeObject#method_missing` raises `NoMethodError` on missing keys — exactly the bug that 500'd the webhook since the Stripe 2026-01-28 API shift. The remaining dot-access calls are the same latent trap; another Stripe field relocation and we're back here.

## Findings
- **Source**: Kieran Rails Reviewer (P1)
- **Location**: `app/controllers/stripe_webhooks_controller.rb:56, 63, 71, 83`
- `handle_subscription_updated` reads `stripe_sub.customer` and `stripe_sub.status` via dot access
- `handle_subscription_deleted` reads `stripe_sub.customer` via dot access
- Defensive hash access in `stripe_period_end` (line 98) is inconsistent with the rest

## Acceptance Criteria
- [ ] All `stripe_sub.*` calls in handlers converted to hash access (`[:customer]`, `[:status]`, `[:id]`)
- [ ] No `NoMethodError` risk remains on any field read from Stripe event payloads
- [ ] Tests still green
