---
status: ready
priority: p3
issue_id: "104"
tags: [code-review, mcp-spec, oauth]
dependencies: []
---

# DCR Response Missing RFC 7591 Recommended Fields

## Problem Statement
The DCR response is missing `client_id_issued_at` and `client_secret_expires_at` (null for public clients) recommended by RFC 7591 Section 3.2.1.

## Findings
- `app/controllers/oauth/registrations_controller.rb` lines 25-31
- Agent: agent-native-reviewer (Warning #6)

## Technical Details
- Affected files: `app/controllers/oauth/registrations_controller.rb`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
