---
status: ready
priority: p3
issue_id: "106"
tags: [code-review, ux, oauth]
dependencies: []
---

# Consider skip_authorization for Repeat Authorizations

## Problem Statement
`skip_authorization` always returns `false`, meaning every token refresh requiring re-authorization forces the user through the consent screen again, even for the same client and scopes. This creates friction for repeat agent workflows.

## Findings
- `config/initializers/doorkeeper.rb` lines 34-36
- Agent: agent-native-reviewer (Observation #10)

## Proposed Solutions
Enable skip for previously-authorized client+scope combinations:
```ruby
skip_authorization do |resource_owner, client|
  Doorkeeper::AccessToken.matching_token_for(client, resource_owner, client.scopes).present?
end
```

## Technical Details
- Affected files: `config/initializers/doorkeeper.rb`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
