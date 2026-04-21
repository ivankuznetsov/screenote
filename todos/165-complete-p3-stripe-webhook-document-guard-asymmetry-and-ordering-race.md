---
status: pending
priority: p3
issue_id: "165"
tags: [code-review, stripe, webhook, documentation]
dependencies: []
---

# Document why the updated/deleted guards are asymmetric and the intended race resolution

## Problem Statement
The guard in `handle_subscription_updated` (`if present? && !=`) is weaker than the one in `handle_subscription_deleted` (`unless ==`). The asymmetry is intentional — the updated handler must allow the initial `customer.subscription.updated` that arrives before `checkout.session.completed` sets the sub id (tested at line 211). But the asymmetry looks inconsistent to a cold reader, and the ordering-race resolution (cancel A → brief free window → checkout B) is also undocumented.

## Findings
- **Source**: Kieran Rails Reviewer (P2), Architecture Strategist (P1 in theirs), Code Simplicity (says justified, keep)
- **Location**: `app/controllers/stripe_webhooks_controller.rb:58-59, 83`
- Asymmetry is load-bearing, not an oversight

## Proposed Solutions
Add a comment block above both handlers describing:
1. Why `updated` allows nil tracked id (out-of-order flow)
2. Why `deleted` requires exact match (don't wipe a different sub)
3. The brief `plan: :free` window that can occur when sub A is deleted before B's checkout lands

## Acceptance Criteria
- [ ] Comment added above `handle_subscription_updated` + `handle_subscription_deleted`
- [ ] A cold reader can understand the guard design without running tests
