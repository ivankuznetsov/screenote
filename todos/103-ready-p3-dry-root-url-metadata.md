---
status: ready
priority: p3
issue_id: "103"
tags: [code-review, simplicity, oauth]
dependencies: []
---

# DRY Up root_url.chomp("/") in Metadata Controller

## Problem Statement
`root_url.chomp("/")` is called 3 times in `OauthMetadataController`. Should be extracted to a private helper method.

## Findings
- `app/controllers/oauth_metadata_controller.rb`: `root_url.chomp("/")` on lines ~9, 17, 32
- Agent: code-simplicity-reviewer

## Technical Details
- Affected files: `app/controllers/oauth_metadata_controller.rb`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
