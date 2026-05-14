---
status: ready
priority: p3
issue_id: "102"
tags: [code-review, testing, oauth]
dependencies: []
---

# Extract Shared OAuth Test Helpers

## Problem Statement
`Doorkeeper::Application.create!` is repeated 4-5 times across test files. The PKCE challenge generation (verifier + SHA256 + base64) is repeated 4 times. Should be extracted into test helpers.

## Findings
- `test/tools/mcp_auth_test.rb`: Creates Doorkeeper::Application 4 times
- `test/integration/oauth_flow_test.rb`: PKCE generation repeated 3 times
- Agent: pattern-recognition-specialist

## Technical Details
- Affected files: `test/test_helper.rb` or new `test/support/oauth_test_helper.rb`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
