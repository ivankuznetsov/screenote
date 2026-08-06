# Self-hosted whole-instance operations

- Added fail-closed, age-encrypted whole-instance backup and restore commands for the four SQLite roles, operator configuration and secrets, and local or evidenced S3 blob state.
- Added strict manifest, filename, checksum, schema, image-chain, compose, storage-namespace, containment, and bounded-stream validation before restore publication.
- Added an in-container restore verifier, redacted diagnostics, adjacent-upgrade/rollback guidance, and an authentication-link prior-key rotation overlay.
- Established the initial uid/gid 1000 host contract and Docker `volume-nocopy` initialization for exact empty target volumes.
- Proved the supported local lifecycle against a final immutable image digest with real Docker: backup, stop/restart, four databases, blobs, annotations and replies, restore verification, and restored service startup all passed.
