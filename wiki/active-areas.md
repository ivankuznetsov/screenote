---
title: Active Areas
type: architecture
source: git log --since="6 months ago"
created: 2026-04-10
updated: 2026-04-11
tags: [active, development, roadmap, recent]
---

# Active Areas

TLDR: Recent development (last 2 months) focused on collaboration UX polish, notification reliability, and annotation threading. The core product loop (upload -> annotate -> agent reads) is complete.

Source: `git log --all --oneline --since="6 months ago"` (40 most recent commits)

## Recently Completed (Feb-Apr 2026)

### Annotation Comment Threads (PR #18)
- Full resolve/reopen workflow with comment threads
- Both users and API keys (agents) can resolve/reopen
- Transactional operations with audit trail
- Commits: `f59b764`, `1a16456`, `701230e`, `c6a5794`

### Hourly Digest Notifications (PR #24, #25)
- Email digests for resolved annotations
- Per-author notification tracking to prevent duplicates
- Fixed edge cases with retry handling
- Commits: `9f50825`, `c2ca60f`, `980dd3d`, `745171d`

### Collaborator Autocomplete (PR #26)
- Autocomplete on invite email field suggesting users from other shared projects
- Rate-limited, owner-only
- Commit: `c425b8b`

### Welcome Email on Sign-up (PR #23)
- Sends welcome email to new users on first registration
- Commit: `ddc0d73`

### Project Thumbnail Previews (PR #20, #22)
- Thumbnail previews on project index cards and page cards
- Uses latest ready screenshot from each page
- Commits: `407fef5`, `25d5cf0`

### Branded Error Pages
- Custom 404 page with dark theme
- Replaced default Rails error pages
- Commits: `cba5086`, `0c921dc`

### OAuth Token Expiry Fix (PR #19)
- Changed MCP OAuth token expiry from 1 hour to 1 year
- Commits: `9186f9f`

## Current Architecture Maturity

| Area | Status |
|------|--------|
| Core annotation workflow | Stable, production-ready |
| MCP integration (OAuth 2.1) | Stable, production-ready |
| REST API (v1) | Stable, minimal surface |
| Team collaboration | Stable, recently polished |
| Billing (Stripe) | Stable |
| Email notifications | Recently added, maturing |
| Admin dashboard | Basic stats only |

## Likely Next Areas

Cross-referenced with `plans/` (4 files) and `todos/` (151 files):

1. **Security hardening (OAuth)** -- 7 ready P1/P2 security todos from OAuth review: IDOR in consent flow (#082), silent token validation failures (#085, #086), missing rate limits (#087, #088), exposed admin routes (#089), arbitrary redirect URIs (#094). See [[technical-debt]].

2. **Page/Version hierarchy** -- Major structural change: Project -> Page -> Version replaces flat screenshot list. Plan is fully specified with 4 phases. Prerequisite: rename PagesController to StaticPagesController. See [[plans-and-initiatives]].

3. **MCP tool completeness** -- 7 missing tools identified: delete_screenshot (#054), delete_annotation (#055), create_annotation (#012), reopen_annotation (#132), add_annotation_comment (#133), create_project (#098), plan status (#120). Plus invitation/membership tools (#153).

4. **Help page redesign** -- Make /help public, add MCP connection docs, expand Claude Code quick start. Plan is ready. Blocked by Page/Version Phase 0 rename.

5. **Claude Code skill** -- `/screenote` slash command for capture + feedback retrieval. Requires `image_path` parameter on CreateScreenshotTool. Plan is ready, independent of other work.

6. **Frontend convention cleanup** -- 23 pending todos covering inline styles, imperative JS, CDN dependencies, px vs rem, missing ARIA attributes.

7. **Notification expansion** -- Digest notifications infrastructure is new; likely to expand to more event types.

See also: [[decisions]], [[gaps]], [[plans-and-initiatives]], [[technical-debt]], [[roadmap]]
