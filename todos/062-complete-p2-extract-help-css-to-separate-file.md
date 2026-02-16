---
status: complete
priority: p2
issue_id: "062"
tags: [code-review, css, architecture, performance]
dependencies: []
---

# Extract Help Page CSS to Separate File

## Problem Statement

The PR added ~230 lines of help-page-specific CSS to `application.css`, growing it 34.6% (863 -> 1162 lines). The app already has page-specific stylesheets (`auth.css`, `landing.css`, `annotorious.css`) conditionally loaded. Help CSS should follow this established pattern.

## Findings

- `application.css` grew from 863 to 1162 lines (+299)
- ~230 lines are help-page specific (`.help-page`, `.help-section`, `.tool-grid`, `.tool-card`, `.workflow`)
- Existing pattern: `auth.css` loaded via `layouts/auth.html.erb`, `landing.css` via `layouts/landing.html.erb`
- Help page uses application layout, so would need conditional `stylesheet_link_tag` or a `content_for :head` block
- Source: Architecture, performance, and pattern recognition reviewers

## Proposed Solutions

### Option A: `content_for :head` block with conditional stylesheet
- **Pros**: Follows Rails conventions, only loads CSS when needed
- **Cons**: Requires adding `yield :head` to application layout
- **Effort**: Small
- **Risk**: Low

### Option B: Help-specific layout
- **Pros**: Clean separation, matches auth/landing pattern exactly
- **Cons**: Another layout file for one page, duplicates application layout
- **Effort**: Small
- **Risk**: Low

## Technical Details

- **Affected files**: `app/assets/stylesheets/application.css`, new `app/assets/stylesheets/help.css`
- **Components**: Asset pipeline, layouts

## Acceptance Criteria

- [ ] Help-specific CSS lives in `help.css`
- [ ] `application.css` does not contain help-page-only styles
- [ ] Help CSS only loads on the help page
