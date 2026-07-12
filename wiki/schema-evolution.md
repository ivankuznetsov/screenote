---
title: Schema Evolution
type: architecture
source: db/migrate/
created: 2026-04-10
updated: 2026-07-09
tags: [database, migrations, schema, history]
---

# Schema Evolution

TLDR: 28 migrations across 8 phases of development, from initial Rails 8 setup through MCP OAuth integration, team collaboration, annotation threading, Stripe webhook hardening, multi-viewport screenshots, project capture snapshots, and resumable manifest identity.

Source: `db/migrate/`

## Migration Timeline

### Phase 1: Foundation (2026-02-11)

| Migration | Purpose |
|-----------|---------|
| `20260211211347_add_rails_simple_auth` | User model with email/password auth (rails_simple_auth gem) |
| `20260211211728_create_projects` | Projects table with user_id foreign key |
| `20260211214953_create_screenshots` | Screenshots table (originally flat, no pages) |
| `20260211215011_create_annotations` | Annotations with percentage-based coordinates |
| `20260211215914_create_active_storage_tables` | Active Storage for image uploads |

### Phase 2: API & Security Hardening (2026-02-12)

| Migration | Purpose |
|-----------|---------|
| `20260212071431_create_api_keys` | API key table for MCP/API bearer auth |
| `20260212071517_add_foreign_key_to_annotations_resolved_by_api_key` | Allow API keys to resolve annotations |
| `20260212153509_fix_resolved_by_foreign_key_cascade` | Fix ON DELETE behavior for resolved_by fields |
| `20260212164633_add_composite_index_to_screenshots` | Performance index on screenshots |
| `20260212202848_create_project_memberships` | Team collaboration: roles (member/owner) |
| `20260212202914_create_project_invitations` | Email-based project invitations |
| `20260212203110_create_owner_memberships_for_existing_projects` | Data migration: backfill owner memberships |
| `20260213090630_fix_project_invitations_index` | Fix unique index on invitations |

### Phase 3: Billing & OAuth (2026-02-14 to 2026-02-16)

| Migration | Purpose |
|-----------|---------|
| `20260214215246_create_subscriptions` | Stripe subscription tracking |
| `20260216114625_create_doorkeeper_tables` | OAuth 2.1 provider tables (Doorkeeper) |
| `20260216120000_fix_doorkeeper_foreign_keys_and_indexes` | Fix Doorkeeper FK constraints, add project scoping |

### Phase 4: Page Hierarchy & Annotation Threading (2026-02-20 to 2026-03-10)

| Migration | Purpose |
|-----------|---------|
| `20260220100000_create_annotation_comments` | Comment threads on annotations with action enum |
| `20260220215314_create_pages` | Pages table (new hierarchy level between Project and Screenshot) |
| `20260220215350_add_page_to_screenshots` | Move screenshots under pages instead of directly under projects |
| `20260221064533_add_ci_uniqueness_to_pages` | Case-insensitive unique index on page names within a project |
| `20260310182720_add_notified_at_to_annotation_comments` | Track notification state for digest emails |

### Phase 5: Stripe Webhook Hardening (2026-04-21)

| Migration | Purpose |
|-----------|---------|
| `20260421065900_create_stripe_webhook_events` | Idempotency ledger keyed by Stripe event id |

### Phase 6: Multi-Viewport Screenshots (2026-04-21)

| Migration | Purpose |
|-----------|---------|
| `20260421110931_create_screenshot_images` | Per-viewport image child table with unique `(screenshot_id, viewport)` |
| `20260421110955_add_viewport_to_annotations` | Scope annotations to desktop/tablet/mobile viewport |
| `20260421114232_backfill_screenshot_images` | Deploy-time backfill from legacy `Screenshot#image` blobs to `ScreenshotImage(:desktop)` |

### Phase 7: Project Capture Snapshots (2026-05-14)

| Migration | Purpose |
|-----------|---------|
| `20260514120600_create_snapshots` | Project-scoped capture runs with git commit and capture time |
| `20260514120630_add_snapshot_id_to_screenshots` | Optional screenshot-to-snapshot link with `ON DELETE SET NULL` |

### Phase 8: Resumable CLI Snapshot Identity (2026-07-10)

| Migration | Purpose |
|-----------|---------|
| `20260710120000_add_manifest_identity_to_snapshots` | Nullable SHA-256 identity columns plus partial unique indexes for snapshots and prepared screenshot entries |

## Key Schema Decisions

1. **Pages added late (2026-02-20)**: Screenshots were originally flat under Project. The Page hierarchy was introduced to group screenshots logically. See commit `dea90b0`.

2. **Annotation comments separate from annotations**: Rather than editing annotation comments in-place, a threaded comment model was added with action tracking (comment/resolved/reopened). See commit `f59b764`.

3. **OAuth project scoping**: Doorkeeper tables have an optional `project_id` FK so OAuth tokens can be scoped to a specific project for MCP access.

4. **Case-insensitive page names**: The `LOWER(name)` unique index on pages ensures no duplicate page names within a project regardless of casing.

5. **Notification tracking**: `notified_at` on annotation_comments enables hourly digest notifications without re-sending.

6. **Stripe webhook idempotency**: `stripe_webhook_events.stripe_event_id` prevents retry-driven duplicate side effects.

7. **ScreenshotImage child rows**: A Screenshot is now a logical capture/version; ScreenshotImage owns actual viewport blobs, dimensions, status, and upload tokens.

8. **Snapshots are additive capture groups**: Existing and ad-hoc screenshots retain a null `snapshot_id`; deleting a snapshot preserves screenshots by nullifying that link.

9. **Manifest identity is nullable and server-owned**: legacy and MCP rows need no backfill, while manifest-backed snapshots and entries use partial unique indexes to make retries deterministic without changing duplicate commit semantics.

See also: [[data-model]], [[decisions]], [[models/snapshot]], [[models/screenshot-image]]
