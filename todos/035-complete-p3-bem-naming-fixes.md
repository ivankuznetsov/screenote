---
status: pending
priority: p3
issue_id: "035"
tags: [code-review, css, conventions]
dependencies: []
---

# BEM Naming Fixes: Phantom Modifiers and Misused --accent Span

## Problem Statement
Two BEM naming issues: (1) `hero__title--accent` is used as a `<span>` child element — per BEM convention it should be a separate element name like `hero__highlight`, not a modifier. (2) `auth-card__oauth-btn--#{provider}` modifier classes are generated in HTML but have zero corresponding CSS rules — they are phantom classes with no effect.

## Findings
- `app/views/pages/landing.html.erb:19`: `<span class="hero__title--accent">` — should be `hero__highlight` or similar
- `sessions/new.html.erb:13`: `auth-card__oauth-btn--#{provider}` — no CSS rule matches this
- Agents: pattern-recognition-specialist (P2)

## Proposed Solutions
1. Rename `hero__title--accent` to `hero__highlight` (a proper BEM element)
2. Either add CSS for `auth-card__oauth-btn--google_oauth2` / `--github` or remove the modifier from the HTML

- Effort: Trivial
- Risk: None

## Technical Details
- **Affected files:** `app/views/pages/landing.html.erb`, `app/assets/stylesheets/application.css`, auth view templates
- **PR:** #6

## Acceptance Criteria
- [ ] No BEM naming violations in new code
- [ ] No phantom CSS class modifiers in HTML

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | BEM modifiers modify existing elements; child elements need element names |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
