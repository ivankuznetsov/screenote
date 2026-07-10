---
title: Snapshot REST preparation and recovery
type: log
date: 2026-07-10
---

# Snapshot REST preparation and recovery

**Action:** Added authenticated API v1 prepare and show resources for manifest-backed project snapshots.

**Contract:** The service validates version, commit, explicit-offset timestamp, bounded flat entries, page/title groups, unique viewports, expected PNG/JPEG types, content hashes, opaque file-reference hashes, and the aggregate length-prefixed manifest digest before mutation.

**Recovery:** Identical and concurrent calls converge on one transactionally created graph. Replay verifies stored metadata, group membership, viewport membership, content SHA, and expected type; mismatch returns `manifest_conflict`. Responses expose stable IDs, aggregate/image state, and a snapshot-filtered review URL without local file references.

**Authorization:** API keys stay bound to their project. OAuth create requires `mcp_write`, show requires `mcp_read`, and project membership remains mandatory.

**Source:** `app/controllers/api/v1/snapshots_controller.rb`, `app/services/snapshots/prepare_upload.rb`, `app/serializers/api/v1/contract_serializer.rb`, `config/routes.rb`, and snapshot REST/service/integration tests.
