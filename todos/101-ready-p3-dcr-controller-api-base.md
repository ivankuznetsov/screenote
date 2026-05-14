---
status: ready
priority: p3
issue_id: "101"
tags: [code-review, rails-conventions, oauth]
dependencies: []
---

# DCR Controller Should Inherit ActionController::API

## Problem Statement
`Oauth::RegistrationsController` inherits from `ApplicationController` but is a pure JSON API endpoint. It skips authentication and CSRF — it would be cleaner to inherit from `ActionController::API` or a base API controller.

## Findings
- `app/controllers/oauth/registrations_controller.rb`: Inherits `ApplicationController`, skips 2 before_actions
- Agent: dhh-rails-reviewer

## Technical Details
- Affected files: `app/controllers/oauth/registrations_controller.rb`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
