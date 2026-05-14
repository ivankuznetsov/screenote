---
status: pending
priority: p3
issue_id: "178"
tags: [code-review, views, polish]
dependencies: []
---

# Extract inline SVG icons from Ruby hash to per-viewport partials

## Problem Statement
`_viewport_switcher.html.erb` builds a `{ "desktop" => svg_string, ... }` hash of raw SVG markup and renders via `html_safe`. Rails convention is either separate partials or `app/assets/images/*.svg` + `image_tag`. Current approach makes the ERB author responsible for XSS safety (safe today because strings are literals, but a foot-gun for any future interpolation).

## Findings
- **Source**: Code Reviewer review of PR #30
- **Location**: `app/views/screenshots/_viewport_switcher.html.erb:13-17, 34`

## Proposed Solution
Extract to 3 partials: `_desktop_icon.html.erb`, `_tablet_icon.html.erb`, `_mobile_icon.html.erb` — each is pure SVG. Switcher renders via `render "#{vp}_icon"`.

## Acceptance Criteria
- [ ] No `html_safe` on raw SVG strings
- [ ] Each viewport icon is a standalone partial
- [ ] Tests still green
