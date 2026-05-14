---
status: ready
priority: p2
issue_id: "149"
tags: [code-review, testing]
dependencies: []
---

# Missing test coverage: SQL injection, self-exclusion, pending invitation exclusion

## Problem Statement
Three important controller behaviors have no test coverage: (1) `sanitize_sql_like` preventing wildcard injection, (2) excluding `Current.user.email` from results, (3) excluding pending invitation recipients.

## Findings
- **Source**: PR Test Analyzer (criticality 8/10 for each)
- **Location**: `test/controllers/collaborator_suggestions_controller_test.rb`

## Proposed Solutions
### Option A: Add 3 targeted tests (Recommended)
1. Test `q: "%25"` or `q: "a%"` doesn't match everything
2. Test searching alice's own email returns no results
3. Test pending invitee email is excluded
- **Effort**: Small | **Risk**: None

## Acceptance Criteria
- [ ] Test that wildcard characters in query don't bypass sanitization
- [ ] Test that current user's email is excluded from suggestions
- [ ] Test that pending invitation emails are excluded
