---
status: pending
priority: p2
issue_id: "160"
tags: [code-review, stripe, webhook, ux, billing]
dependencies: []
---

# Stripe `trialing` status maps to `:incomplete` — user loses access during trial

## Problem Statement
The `case stripe_sub.status` block at lines 63-68 maps anything not in `{active, past_due, canceled, unpaid}` to `:incomplete`. Stripe's `trialing` status means the subscription is in its trial period with full access — mapping it to `:incomplete` (which blocks access) is a UX bug. Same applies to `paused` and `incomplete_expired`.

## Findings
- **Source**: Data Integrity Guardian (P3 for integrity, P2 for UX)
- **Location**: `app/controllers/stripe_webhooks_controller.rb:61-68`
- Currently if screenote ever enables Stripe trials, trialing users would be locked out

## Proposed Solutions
**Option A**: Map `trialing → :active`. Simplest; trial users see the app as pro.

**Option B**: Add `trialing` to the subscription `status` enum. More precise; allows UI differentiation (e.g. show "Trial ends in 5 days" banner).

## Acceptance Criteria
- [ ] `trialing` events don't revoke access from users in a Stripe trial
- [ ] Decision documented in commit message (map to active vs add enum)
- [ ] Test coverage for the trialing path
