---
status: complete
priority: p2
issue_id: "114"
tags: [code-review, rails, views, pr-11]
dependencies: []
---

# Hardcoded "$10/mo" in Upgrade Banners While `PRO_PRICE_CENTS` Constant Exists

## Problem Statement
The billing page correctly derives the price from `Subscription::PRO_PRICE_CENTS / 100`, but two upgrade banners hardcode `$10/mo`. If the price changes, these banners will show stale prices. The price is expressed three different ways across three files.

## Findings
- `app/views/projects/index.html.erb`, line 15: `"Upgrade to Pro for $10/mo"` (hardcoded)
- `app/views/project_memberships/index.html.erb`, line 21: `"Upgrade to Pro for $10/mo"` (hardcoded)
- `app/views/subscriptions/show.html.erb`, line 35: `$<%= Subscription::PRO_PRICE_CENTS / 100 %>` (from constant)
- Identified by: DHH, Kieran, Pattern Recognition, Code Simplicity

## Proposed Solutions

### Option A: Use the constant everywhere (Recommended)
Replace hardcoded strings with `$#{Subscription::PRO_PRICE_CENTS / 100}/mo` or create a helper.
- **Effort**: Small
- **Risk**: Low

### Option B: Hardcode everywhere and remove the constant
Just use `$10/mo` in all three places; remove `PRO_PRICE_CENTS` since real price lives in Stripe.
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Price displayed consistently across all views
- [ ] Single source of truth for price display

## Work Log
- 2026-02-16: Created from PR #11 code review
