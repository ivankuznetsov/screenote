---
status: complete
priority: p3
issue_id: "078"
tags: [code-review, css, dead-code]
dependencies: []
---

# Phantom .tool-card__example CSS Class

## Problem Statement
The HTML in `help.html.erb` uses the BEM class `.tool-card__example` on `<pre>` elements, but there is no corresponding CSS rule in `help.css`. The styling works because `<pre>` has browser defaults, but the class suggests intentional styling that was never implemented.

## Findings
- **Location**: `app/views/pages/help.html.erb` (tool cards, `<pre class="tool-card__example">`)
- **Location**: `app/assets/stylesheets/help.css` (no `.tool-card__example` rule)
- Class is used in HTML but has no CSS definition
- Found by pattern-recognition-specialist

## Proposed Solutions

### Option 1: Add CSS Rule for .tool-card__example
- **Pros**: Intentional styling, consistent with BEM pattern
- **Cons**: May not need custom styling
- **Effort**: Small
- **Risk**: Low

### Option 2: Remove the Class from HTML
- **Pros**: No phantom classes
- **Cons**: Loses semantic meaning
- **Effort**: Small
- **Risk**: Low

## Recommended Action
Remove the `.tool-card__example` wrapper div from the HTML since it serves no styling purpose. The `<pre class="tool-card__example-code">` inside it already has CSS rules.

## Technical Details
- **Affected Files**: `app/assets/stylesheets/help.css` or `app/views/pages/help.html.erb`
- **Database Changes**: No

## Acceptance Criteria
- [ ] No phantom CSS classes (class either has a rule or is removed)

## Work Log

### 2026-02-15 - Approved for Work
**By:** Claude Triage System
**Actions:**
- Issue approved during triage session
- Status changed from pending to ready

### 2026-02-15 - Identified in Code Review
**By:** Multi-agent review (PR #10)

## Resources
- PR #10: Add MCP help page and dashboard banner
