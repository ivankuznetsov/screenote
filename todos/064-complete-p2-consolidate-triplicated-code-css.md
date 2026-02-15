---
status: complete
priority: p2
issue_id: "064"
tags: [code-review, css, dry]
dependencies: []
---

# Consolidate Triplicated Inline `code` CSS

## Problem Statement

The same inline `code` styling (background, padding, border-radius, font-size, font-family) is defined three times in the help page CSS — once for `.help-page code`, once inside `.tool-card`, and once inside `.workflow`. This violates DRY.

## Findings

- Lines ~1033-1037: `.help-page` code styling
- Lines ~1091-1095: `.tool-card` code styling
- Lines ~1157-1161: `.workflow` code styling
- All three are identical or near-identical rules
- Source: Pattern recognition and code simplicity reviewers

## Proposed Solutions

### Option A: Single `.help-page code` rule
- **Pros**: One definition covers all code elements within help page
- **Cons**: None (all three contexts are children of `.help-page`)
- **Effort**: Small
- **Risk**: None

## Technical Details

- **Affected files**: `app/assets/stylesheets/application.css`
- **Components**: Help page CSS

## Acceptance Criteria

- [ ] Single `code` styling rule replaces three duplicated blocks
- [ ] All inline code elements render identically
