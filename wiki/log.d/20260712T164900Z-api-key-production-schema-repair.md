---
title: API key production schema repair
type: log
date: 2026-07-12
---

# API key production schema repair

**Action:** Documented and repaired historical API-key schema drift discovered by the production CLI OAuth smoke. A new irreversible forward migration converts any legacy plaintext tokens to SHA-256 digests and prefixes, preserves already-secure fresh databases, fails closed on unknown schemas, and bounds PostgreSQL lock acquisition. Added isolated SQLite coverage plus a dedicated PostgreSQL 16 CI lane for the production-specific migration path.

**Pages updated:** `wiki/models/api-key.md`, `wiki/schema-evolution.md`, and this log fragment.

**Source:** Production schema metadata, PR #3 and PR #4 history, `.github/workflows/ci.yml`, `db/migrate/20260212071431_create_api_keys.rb`, deleted migration `20260212151018_add_token_digest_to_api_keys.rb`, `app/models/api_key.rb`, and `app/services/api/bearer_authenticator.rb`.
