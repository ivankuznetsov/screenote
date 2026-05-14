---
status: pending
priority: p3
issue_id: "176"
tags: [code-review, css, a11y, polish]
dependencies: []
---

# Verify viewport switcher icon color inheritance

## Problem Statement
PR-3's viewport switcher renders device icons via inline SVG data URIs in CSS (`application.css:~637`). The SVGs use `stroke='currentColor'` — but `currentColor` inside a data URI does NOT inherit from the parent element's computed color. So the active-state color change (`.viewport-switcher__btn--active { color: var(--color-accent-fg) }`) won't affect the icon.

Kieran flagged this as a "verify in browser" item.

## Findings
- **Source**: Kieran Rails Reviewer P3 on PR #30
- **Location**: `app/assets/stylesheets/application.css` viewport-switcher block

## Proposed Solution
Two clean options:
1. Move SVGs inline in `_viewport_switcher.html.erb` as `<svg fill="currentColor">` so they truly inherit from the btn color.
2. Use two data URIs per icon — one stroked with muted color for inactive, one with accent color for active — and swap via the `--active` modifier.

Option 1 is cleaner; partial grows by ~9 lines (3 SVGs) but CSS shrinks correspondingly.

## Acceptance Criteria
- [ ] Active viewport icon is visibly distinct (different color) from inactive ones
- [ ] Visual regression screenshot taken and compared
