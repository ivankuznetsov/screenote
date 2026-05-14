---
status: complete
priority: p3
issue_id: "125"
tags: [code-review, testing, pr-11]
dependencies: []
---

# Delete Meaningless Constant-Value Test

## Problem Statement
The subscription test at lines 6-10 asserts that `FREE_PROJECT_LIMIT == 1`, `FREE_MEMBER_LIMIT == 1`, and `PRO_PRICE_CENTS == 1000`. This test never catches bugs — if someone changes a constant, the test just tells them to update the test. The actual limit behavior is already tested in `UserTest`.

## Findings
- **File**: `test/models/subscription_test.rb`, lines 6-10
- Identified by: Code Simplicity Reviewer

## Proposed Solutions

### Option A: Delete the test (Recommended)
- **Effort**: Small
- **Risk**: None

## Acceptance Criteria
- [ ] Constant-value test removed
- [ ] Remaining tests still pass

## Work Log
- 2026-02-16: Created from PR #11 code review
