---
title: Public CLI manifest identity
type: log
date: 2026-07-10
---

# Public CLI manifest identity

**Action:** Added nullable manifest, entry, and image content SHA-256 identities for resumable CLI snapshot preparation.

**Behavior:** Legacy and MCP-created rows remain valid without digests. Manifest-backed snapshots require uniquely identified screenshot entries and content-bound ScreenshotImages. Snapshot state is derived as awaiting upload, processing, failed, or ready from real child attachment and processing state.

**Integrity:** Partial unique indexes protect project snapshot and snapshot entry identities without changing repeated git-commit capture semantics. Existing snapshot deletion nullification and same-project validation remain unchanged.

**Source:** `db/migrate/20260710120000_add_manifest_identity_to_snapshots.rb`, `app/models/snapshot.rb`, `app/models/screenshot.rb`, `app/models/screenshot_image.rb`, and focused model tests.
