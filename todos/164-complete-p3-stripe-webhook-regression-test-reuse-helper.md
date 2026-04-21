---
status: pending
priority: p3
issue_id: "164"
tags: [code-review, stripe, webhook, tests]
dependencies: []
---

# Regression test hand-rolls a 22-line event hash the helper already produces

## Problem Statement
The Stripe 2026-01 regression test at lines 134-155 builds an event literal inline that duplicates what `build_subscription_updated_event` already produces. Two opinions from reviewers:
- **Simplicity reviewer**: replace with `build_subscription_updated_event(...)` call — drops 20 LOC
- **Kieran**: keep it — the inline hash documents the exact Stripe 2026-01-28 payload shape for future engineers; a helper call obscures that contract

## Findings
- **Source**: Code Simplicity Reviewer (P1) / Kieran Rails Reviewer (P3 — keep it)
- **Location**: `test/controllers/stripe_webhooks_controller_test.rb:134-155`
- Needs a judgement call during triage

## Proposed Solutions
**Option A**: Replace with helper (simplicity wins).
**Option B**: Keep inline but add a link/comment pointing to the actual Stripe 2026-01-28 release notes so the "why" is explicit.
**Option C**: Keep as-is (Kieran's preference).

## Acceptance Criteria
- [ ] Decision made during triage
- [ ] Test name remains clearly tied to the API version change
