---
status: ready
priority: p3
issue_id: "107"
tags: [code-review, ux, oauth]
dependencies: []
---

# Add MCP Explanation to Consent Page

## Problem Statement
When Claude Code opens the consent page in the user's browser, the user sees "Authorize Application" and scope descriptions but no explanation of what MCP is or why their agent needs access. A brief explanation would reduce confusion.

## Findings
- `app/views/doorkeeper/authorizations/new.html.erb`: No contextual copy about MCP
- Agent: agent-native-reviewer (Observation #9)

## Proposed Solutions
Add a line like: "An AI agent is requesting access to read and write screenshots and annotations in your project via the Model Context Protocol."

## Technical Details
- Affected files: `app/views/doorkeeper/authorizations/new.html.erb`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
