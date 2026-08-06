## [2026-08-06] Make credential-cutover witness queries static

**Action:** Replaced the credential cutover's generic table/column/predicate SQL builder with a closed set of literal witness queries. The cutover still captures only one in-memory verification witness per credential kind, but its pre-migration reads can no longer be mistaken for or extended into an input-driven SQL surface.

**Resume boundary:** A rerun after the credential migration now applies and verifies every later migration before returning success. Merely finding the credential migration in `schema_migrations` cannot boot a successor with a partially upgraded schema.

**Atomic boundary:** PostgreSQL now holds one outer transaction across legacy-witness capture, the complete migration chain, stored-digest checks, and raw-credential runtime lookup proofs. Any migration or final verification failure restores both the legacy schema and reusable credentials for an evidence-preserving retry.

**Backup boundary:** The deployment command now stops and proves every predecessor process quiesced before it invokes a pre-reviewed, digest-pinned backup hook. The hook must create new private evidence bound to the command's timestamp and random challenge, an opaque database restore-point digest, both immutable revisions, and all four database roles; pre-stop evidence cannot authorize migration.

**Pages updated:** wiki/self-hosting.md, wiki/log.d/20260806T005800Z-static-cutover-queries.md, wiki/log.md

**Source:** `app/services/screenote/saas_credential_cutover.rb`, focused cutover tests, RuboCop, and a zero-warning Brakeman scan
