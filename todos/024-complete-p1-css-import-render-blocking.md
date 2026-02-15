---
status: pending
priority: p1
issue_id: "024"
tags: [code-review, performance, css]
dependencies: []
---

# CSS @import url() for Google Fonts Is Render-Blocking

## Problem Statement
The Google Fonts are loaded via a CSS `@import url()` at line 834 of `application.css`. This creates a chained blocking request: browser downloads CSS → discovers @import → fetches Google Fonts CSS → discovers font files → fetches .woff2 files. This adds 1-3s of blank screen on slow connections. Additionally, the @import is mid-file (after 833 lines of rules), violating the CSS spec requirement that @import must precede other rules. Every page in the app (including authenticated dashboard) pays this cost even though those pages don't use these fonts.

## Findings
- `app/assets/stylesheets/application.css:834`: `@import url('https://fonts.googleapis.com/css2?...')`
- Flagged by ALL 8 review agents as the highest-priority performance issue
- Agents: security-sentinel, performance-oracle, architecture-strategist, kieran-rails-reviewer, dhh-rails-reviewer, pattern-recognition-specialist, code-simplicity-reviewer, agent-native-reviewer

## Proposed Solutions

### Option A: Move to `<link>` tags in layout `<head>` (Recommended)
Add `<link rel="preconnect">` and `<link rel="stylesheet">` tags in only the landing and auth layout `<head>` sections. Remove the @import from application.css entirely.
```erb
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,400;0,9..40,500;0,9..40,700&family=Playfair+Display:wght@700;900&display=swap" rel="stylesheet">
```
- Pros: Parallel loading, scoped to layouts that need fonts, follows best practices
- Cons: Still a third-party dependency
- Effort: Small
- Risk: Low

### Option B: Self-host fonts
Download fonts via google-webfonts-helper, serve from app's own domain, remove Google Fonts CSP entries entirely.
- Pros: No third-party dependency, tighter CSP, no privacy leakage to Google
- Cons: More setup, manual font updates
- Effort: Medium
- Risk: Low

## Recommended Action
Option A for immediate fix; Option B as future improvement.

## Technical Details
- **Affected files:** `app/assets/stylesheets/application.css`, `app/views/layouts/landing.html.erb`, `app/views/layouts/auth.html.erb`
- **PR:** #6

## Acceptance Criteria
- [ ] No `@import url()` in application.css
- [ ] Google Fonts loaded via `<link>` tags only in landing and auth layouts
- [ ] Authenticated pages do not request Google Fonts
- [ ] `<link rel="preconnect">` hints present for font origins

## Work Log
| Date | Action | Learnings |
|------|--------|-----------|
| 2025-02-12 | Created from PR #6 code review | All 8 agents flagged this as critical |

## Resources
- PR: https://github.com/ivankuznetsov/screenote/pull/6
- [web.dev: Best practices for fonts](https://web.dev/font-best-practices/)
