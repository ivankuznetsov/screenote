---
status: complete
priority: p2
issue_id: "061"
tags: [code-review, css, consistency]
dependencies: []
---

# Hardcoded Colors in MCP Banner CSS

## Problem Statement

The `.mcp-banner` gradient uses raw hex colors (`#eff6ff`, `#e0e7ff`, `#bfdbfe`) instead of CSS custom properties. The rest of the app uses `var(--color-*)` tokens. This breaks theming consistency and makes future color changes harder.

## Findings

- Banner background: `linear-gradient(135deg, #eff6ff, #e0e7ff)` uses hardcoded values
- Banner border: `1px solid #bfdbfe` is also hardcoded
- Existing design tokens in `:root` use `--color-*` pattern
- Source: Pattern recognition, performance, and architecture reviewers

## Proposed Solutions

### Option A: Add banner-specific CSS custom properties to `:root`
- **Pros**: Consistent with existing pattern, supports theming
- **Cons**: Adds more custom properties
- **Effort**: Small
- **Risk**: None

## Technical Details

- **Affected files**: `app/assets/stylesheets/application.css`
- **Components**: `.mcp-banner` CSS block

## Acceptance Criteria

- [ ] Banner gradient and border use `var(--color-*)` tokens
- [ ] No hardcoded hex values in `.mcp-banner` rules
