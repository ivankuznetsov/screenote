---
status: complete
priority: p2
issue_id: "065"
tags: [code-review, css, dry]
dependencies: []
---

# Merge Duplicate `.tool-card__params-title` and `.tool-card__example-title`

## Problem Statement

`.tool-card__params-title` and `.tool-card__example-title` have identical CSS rules. They should share a single class or be combined in a grouped selector.

## Findings

- Both classes define the same font-size, font-weight, color, margin, and text-transform
- Used in help page tool reference cards for section headings
- Source: Pattern recognition and code simplicity reviewers

## Proposed Solutions

### Option A: Single `.tool-card__label` class for both
- **Pros**: DRY, cleaner BEM naming
- **Cons**: Requires HTML change
- **Effort**: Small
- **Risk**: None

### Option B: Grouped CSS selector
- **Pros**: No HTML changes needed
- **Cons**: Two class names for the same style
- **Effort**: Small
- **Risk**: None

## Technical Details

- **Affected files**: `app/assets/stylesheets/application.css`, `app/views/pages/help.html.erb`
- **Components**: Help page CSS, tool card component

## Acceptance Criteria

- [ ] No duplicate CSS declarations between the two label classes
