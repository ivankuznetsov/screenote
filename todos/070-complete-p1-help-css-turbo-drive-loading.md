---
status: complete
priority: p1
issue_id: "070"
tags: [code-review, turbo, css, rails]
dependencies: []
---

# help.css May Not Load Under Turbo Drive Navigation

## Problem Statement
The help page loads `help.css` via `content_for :head`, which injects a `<link>` tag into the `<head>` section. However, Turbo Drive only swaps the `<body>` on navigation -- it does NOT re-evaluate `<head>` content. This means when a user navigates to the help page via a Turbo Drive link (e.g., from the dashboard), the stylesheet won't load and the page will appear unstyled.

## Findings
- **Location**: `app/views/pages/help.html.erb` line 1-3 (`content_for :head`)
- **Location**: `app/views/layouts/application.html.erb` (yields `:head` in `<head>`)
- The page works on direct/full page load but fails on Turbo navigation
- This affects ALL internal navigation links to the help page (header nav link, banner link)
- Consensus finding across architecture-strategist, kieran-rails-reviewer, dhh-rails-reviewer

## Proposed Solutions

### Option 1: Move Help CSS Into application.css (Recommended)
- **Pros**: Always available, simplest fix, follows Rails 8 convention
- **Cons**: Slightly larger CSS bundle (198 lines, ~4KB)
- **Effort**: Small
- **Risk**: Low

### Option 2: Use data-turbo="false" on Help Links
- **Pros**: Forces full page reload, CSS loads correctly
- **Cons**: Breaks Turbo Drive navigation experience, feels hacky
- **Effort**: Small
- **Risk**: Medium (inconsistent UX)

### Option 3: Use Turbo Permanent Element for Head
- **Pros**: Keeps CSS separate
- **Cons**: Complex, not well-supported for head elements
- **Effort**: Medium
- **Risk**: High

## Recommended Action
Move help.css contents into application.css. It's only 198 lines (~4KB) -- negligible impact. Remove the `content_for :head` block from help.html.erb. Delete help.css file.

## Technical Details
- **Affected Files**: `app/views/pages/help.html.erb`, `app/assets/stylesheets/help.css`, `app/assets/stylesheets/application.css`
- **Related Components**: Turbo Drive, layout head yields
- **Database Changes**: No

## Acceptance Criteria
- [ ] Help page styles load correctly when navigating via Turbo Drive
- [ ] Help page styles load correctly on direct page load
- [ ] No FOUC (flash of unstyled content)
- [ ] Tests pass

## Work Log

### 2026-02-15 - Approved for Work
**By:** Claude Triage System
**Actions:**
- Issue approved during triage session
- Status changed from pending to ready

### 2026-02-15 - Identified in Code Review
**By:** Multi-agent review (PR #10)
**Actions:**
- Found by architecture-strategist, kieran-rails-reviewer, dhh-rails-reviewer
- All agents flagged as critical because the help page will appear broken for most users

## Resources
- PR #10: Add MCP help page and dashboard banner
- Turbo Drive docs on head merging
