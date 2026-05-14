---
status: complete
priority: p3
issue_id: "126"
tags: [code-review, views, ux, pr-11]
dependencies: []
---

# Duplicate "Manage Billing" Button in Subscription View

## Problem Statement
The subscription show page has a "Manage subscription" button inside the Pro plan card AND a separate `billing-info` section below with a second "Manage billing" button that does the exact same thing. Pro users see two buttons leading to the same Stripe portal.

## Findings
- **File**: `app/views/subscriptions/show.html.erb`, lines 45 and 52-59
- Identified by: Code Simplicity Reviewer
- Removing the section also eliminates `.billing-info` CSS classes (~12 lines)

## Proposed Solutions

### Option A: Merge billing-info into the Pro plan card (Recommended)
Move the renewal date into the plan card and drop the separate section.
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Single "Manage subscription" button for pro users
- [ ] Renewal date still visible (inside plan card)
- [ ] `.billing-info` CSS removed

## Work Log
- 2026-02-16: Created from PR #11 code review
