---
status: pending
priority: p2
issue_id: "009"
tags: [code-review, security]
dependencies: []
---

# Configure Content Security Policy

## Problem Statement
The entire CSP configuration is commented out. Without CSP, any XSS vulnerability has full freedom to execute arbitrary scripts. The app loads external scripts from Honeybadger and jsdelivr CDN.

## Findings
- `config/initializers/content_security_policy.rb`: Entirely commented out
- External scripts: `https://js.honeybadger.io`, `https://cdn.jsdelivr.net`
- Agents: security-sentinel (M1)

## Proposed Solutions
Enable strict CSP with allowlisted script sources.
- Effort: Small | Risk: Low (test that Annotorious and Honeybadger still load)

## Acceptance Criteria
- [ ] CSP configured with script-src, style-src, img-src, connect-src
- [ ] Annotorious and Honeybadger JS still functional
- [ ] No console CSP violations on main pages

## Work Log
- 2026-02-12: Created from code review (security-sentinel)
