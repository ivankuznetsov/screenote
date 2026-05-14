---
status: ready
priority: p1
issue_id: "082"
tags: [code-review, security, oauth]
dependencies: []
---

# IDOR: project_id Tampering in OAuth Consent Flow

## Problem Statement
The OAuth consent form allows the user to select a `project_id` from a dropdown restricted to their own projects. However, `project_id` is submitted as a plain form parameter and Doorkeeper's `custom_access_token_attributes` passes it directly into the access grant/token **without any server-side ownership validation**. An authenticated attacker can POST any `project_id` to obtain a token scoped to another user's project.

## Findings
- `app/views/doorkeeper/authorizations/new.html.erb` lines 37-41: `<select name="project_id">` populated client-side only
- `app/controllers/oauth/authorizations_controller.rb`: `load_projects` only runs on `new`, not `create`
- `config/initializers/fast_mcp.rb` line 66: `Project.find_by(id: access_token.project_id)` trusts the stored project_id
- Doorkeeper's `PreAuthorization` slices `project_id` from params and passes it through without validation
- Agents: security-sentinel (C1), architecture-strategist, agent-native-reviewer, silent-failure-hunter

## Proposed Solutions

### Option A: before_action validation (Recommended)
Add `before_action :validate_project_ownership, only: :create` to `AuthorizationsController`:
```ruby
def validate_project_ownership
  return unless current_resource_owner
  project_id = params[:project_id]
  unless current_resource_owner.projects.exists?(id: project_id)
    Rails.logger.warn("OAuth: user #{current_resource_owner.id} attempted project #{project_id}")
    redirect_to oauth_authorization_path, alert: "Invalid project selection."
  end
end
```
- Pros: Simple, minimal code, catches the attack at the right layer
- Cons: None
- Effort: Small
- Risk: Low

## Recommended Action
Option A

## Technical Details
- Affected files: `app/controllers/oauth/authorizations_controller.rb`
- Components: OAuth authorization flow, project scoping

## Acceptance Criteria
- [ ] Server rejects consent POST with project_id the user does not own
- [ ] Logs the attempt with user_id and project_id
- [ ] Test covers the IDOR scenario

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review (4 agents flagged)
- 2026-02-16: Approved during triage — Status: pending → ready

## Resources
- PR: OAuth 2.1 implementation
- OWASP IDOR: https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/05-Authorization_Testing/04-Testing_for_Insecure_Direct_Object_References
