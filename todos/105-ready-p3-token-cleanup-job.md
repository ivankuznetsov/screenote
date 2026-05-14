---
status: ready
priority: p3
issue_id: "105"
tags: [code-review, maintenance, oauth]
dependencies: []
---

# Add Token Cleanup Recurring Job

## Problem Statement
No mechanism exists to clean up expired/revoked OAuth tokens or unused dynamic applications. Over time, these tables will grow unbounded.

## Findings
- No cleanup job exists for `oauth_access_tokens` or `oauth_applications` where `dynamic: true`
- Agents: performance-oracle, architecture-strategist

## Proposed Solutions
Add a Solid Queue recurring job that:
1. Deletes expired + revoked tokens older than 7 days
2. Deletes `dynamic: true` applications with no active tokens after 30 days

## Technical Details
- Affected files: New job + `config/recurring.yml`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
