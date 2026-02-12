---
status: pending
priority: p2
issue_id: "008"
tags: [code-review, security]
dependencies: []
---

# Enable config.hosts for DNS Rebinding Protection

## Problem Statement
Production environment has no `config.hosts` set, allowing DNS rebinding attacks. An attacker controlling a domain could configure DNS to resolve to the server's IP, bypassing CSRF protections.

## Findings
- `config/environments/production.rb`: No `config.hosts` or `host_authorization` configured
- Agents: security-sentinel (H2)

## Proposed Solutions
Add to production.rb:
```ruby
config.hosts = ["screenote.ai", /.*\.screenote\.ai/]
config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
```
- Effort: Small | Risk: Low

## Acceptance Criteria
- [ ] config.hosts set in production.rb
- [ ] Health check excluded from host authorization
- [ ] MCP endpoints still accessible

## Work Log
- 2026-02-12: Created from code review (security-sentinel)
