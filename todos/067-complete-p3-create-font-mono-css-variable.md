---
status: complete
priority: p3
issue_id: "067"
tags: [code-review, css, consistency]
dependencies: []
---

# Create `--font-mono` CSS Custom Property

## Problem Statement

The monospace font stack `"SF Mono", "Fira Code", "Fira Mono", Menlo, Consolas, monospace` is repeated 3 times in the CSS. A `--font-mono` custom property would centralize this.

## Findings

- Same font stack on lines ~1020, ~1055, ~1119
- Existing pattern: `--font-family` custom property exists for body text
- Source: Performance and pattern recognition reviewers

## Proposed Solutions

### Option A: Add `--font-mono` to `:root`
- **Pros**: Single source of truth, consistent with `--font-family`
- **Cons**: None
- **Effort**: Small
- **Risk**: None

## Technical Details

- **Affected files**: `app/assets/stylesheets/application.css`
- **Components**: CSS custom properties

## Acceptance Criteria

- [ ] `--font-mono` variable defined in `:root`
- [ ] All monospace `font-family` declarations use `var(--font-mono)`
