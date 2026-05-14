---
status: ready
priority: p2
issue_id: "145"
tags: [code-review, rails, conventions]
dependencies: []
---

# Partial uses @suggestions instance variable instead of locals

## Problem Statement
The `_suggestions.html.erb` partial references `@suggestions` directly. Rails partials should receive data via locals for reusability and explicit dependencies.

## Findings
- **Source**: DHH, Kieran, Architecture (all 3 flagged)
- **Location**: `app/views/collaborator_suggestions/_suggestions.html.erb:1` and `app/controllers/collaborator_suggestions_controller.rb:31`

## Proposed Solutions
### Option A: Pass locals explicitly (Recommended)
Controller: `render partial: "collaborator_suggestions/suggestions", locals: { suggestions: @suggestions }, layout: false`
Partial: change `@suggestions` to `suggestions`
- **Effort**: Small | **Risk**: None

## Acceptance Criteria
- [ ] Partial uses local variable `suggestions` not `@suggestions`
- [ ] Controller passes locals explicitly
