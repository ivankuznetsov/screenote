---
status: pending
priority: p2
issue_id: "156"
tags: [code-review, stripe, webhook, architecture, rails]
dependencies: []
---

# Stripe webhook controller owns the subscription state machine — move to model

## Problem Statement
`StripeWebhooksController` is ~100 lines across five private methods encoding Stripe-status → local-enum mapping, plan promotion rules, and transition-triggered mailer side effects. Meanwhile `app/models/subscription.rb` is 21 lines with a single predicate. Violates fat-model / skinny-controller (called out explicitly in CLAUDE.md). Three agents flagged this independently (Kieran, DHH, architect).

## Findings
- **Source**: Kieran Rails Reviewer, DHH Rails Reviewer, Architecture Strategist
- **Location**: `app/controllers/stripe_webhooks_controller.rb:42-98`
- Status-mapping case at lines 63-68, promotion rule at line 69, mailer trigger at line 77 all belong on `Subscription`
- Controller should dispatch events; model decides state transitions

## Proposed Solutions
**Option A — model methods** (preferred per Kieran):
- `Subscription#apply_stripe_update(stripe_sub)` → returns `:promoted | :updated | :unchanged`
- `Subscription#apply_stripe_deletion(stripe_sub_id)`
- `Subscription#activate_from_checkout(session)`
Controller shrinks to routing + dispatch + `@subscription.apply_stripe_update(...).then { |r| enqueue_mail if r == :promoted }`.

**Option B — Service object** (`StripeWebhookProcessor`) — rejected by Kieran: "fat model is the Rails answer here".

## Acceptance Criteria
- [ ] Controller has no `case stripe_sub.status` — mapping lives on `Subscription`
- [ ] Promotion detection / mailer trigger moved to model method or `after_update_commit` callback
- [ ] Controller reduced to dispatch (≤ 50 lines)
- [ ] All existing webhook tests pass unchanged
