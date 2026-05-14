---
status: ready
priority: p1
issue_id: "143"
tags: [code-review, security, javascript, rails]
dependencies: []
---

# fetch() follows require_owner! redirect, injects full page HTML into dropdown

## Problem Statement
When `require_owner!` rejects a request, it issues a 302 redirect to `projects_path`. The Stimulus controller's `fetch()` follows this redirect silently (default browser behavior), receives a 200 OK with the full projects index HTML, and injects it into the autocomplete dropdown via `template.innerHTML`. This happens if ownership is revoked while the members page is open.

## Findings
- **Source**: Silent Failure Hunter, Architecture Strategist, Kieran Rails Reviewer (all 3 flagged independently)
- **Location**: `app/javascript/controllers/email_autocomplete_controller.js:34-39` and `app/controllers/concerns/project_authorization.rb:12-16`
- `fetch()` follows 302 redirects by default, `response.ok` is true for the redirected page
- The JS then injects the full HTML page into the dropdown container

## Proposed Solutions

### Option A: Add `redirect: "error"` to fetch options (Recommended)
- **Pros**: Single-line fix in JS, prevents redirect following
- **Cons**: Turns redirects into network errors caught by catch block
- **Effort**: Small
- **Risk**: Low

### Option B: Override `require_owner!` in the controller to return 403 for fetch requests
- **Pros**: Proper HTTP semantics, can be reused
- **Cons**: Modifies shared concern behavior or adds controller-specific override
- **Effort**: Small
- **Risk**: Low

### Option C: Check response URL against request URL in JS
- **Pros**: Detects any redirect, not just auth redirects
- **Cons**: More code, fragile
- **Effort**: Medium
- **Risk**: Medium

## Technical Details
- **Affected files**: `app/javascript/controllers/email_autocomplete_controller.js`, potentially `app/controllers/concerns/project_authorization.rb`
- **Components**: Stimulus controller, ProjectAuthorization concern

## Acceptance Criteria
- [ ] When a non-owner makes an autocomplete fetch, the dropdown does not show garbled HTML
- [ ] The fetch correctly handles 302 redirects from authorization failures
- [ ] Existing authorization behavior for full-page requests is unchanged
