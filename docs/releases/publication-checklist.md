# Publication checklist

This checklist records the human-controlled gates around the automated release workflow. Checkboxes are intentionally empty in source. A checked box without matching restricted evidence and public evidence hashes is not approval.

## Legal and source authority

- [ ] Future Spin Ltd chain of title and contribution authority reviewed.
- [ ] Exact `LICENSE` text and `Copyright © 2026, Future Spin Ltd.` notice approved by counsel.
- [ ] Directly competing hosted-service restriction described consistently as source-available, not open source.
- [ ] Third-party dependency, vendored asset, base-image, generated artifact, and history licenses reviewed.
- [ ] Candidate public history contains no unresolved protected/confidential data or third-party IP.

## Repository and credential surface

- [ ] Writes frozen and every branch/tag/ref recorded for the candidate SHA.
- [ ] Actions logs/artifacts, issues, pull requests, wiki, releases, packages, Pages, and cached build output reviewed.
- [ ] Removed Rails encrypted credentials inventoried with authorized decryption.
- [ ] Every reusable credential revoked or rotated and provider evidence retained.
- [ ] Security and legal reviewers approved history retention, or a reviewed rewrite/clean root replaced it.

## GitGuardian and repository protection

- [ ] GitGuardian GitHub App installed on the exact repository source and historical scan finished.
- [ ] GitGuardian App PR check source/name verified; skip actions disabled.
- [ ] Full-history and current-tree `ggshield` scans passed for the exact candidate SHA.
- [ ] All repository incident pages queried; no `TRIGGERED` or `ASSIGNED` item remains.
- [ ] Main ruleset rejects direct/force pushes and deletion and requires every product and GitGuardian check.
- [ ] `v*` tag ruleset rejects direct creation, update, force-push, and deletion except the narrow release integration.
- [ ] Protected `source-release` environment, least-privilege Actions settings, GHCR package access, immutable GitHub releases, and private vulnerability reporting independently inspected.

## Exact artifact and compatibility

- [ ] AMD64 and ARM64 OCI layouts built once from the exact protected default-branch SHA.
- [ ] Retained layout config/layer digests match after import into the trusted scanner runtime.
- [ ] Exact platform images passed GitGuardian and pinned Critical/High vulnerability policy.
- [ ] Final manifest labels, platform digests, SBOM, provenance, and public-log sentinel scan passed.
- [ ] Protected-main product, migration, adapter, collaboration, container, storage, and security-data jobs are recorded only as `pr_contract_only` source checks.
- [ ] Separate exact qualification run booted the retained AMD64 and ARM64 candidate in both self-hosted and SaaS modes.
- [ ] Separate exact qualification run passed same-image backup/restore and the ten-minute SQLite load profile on the documented minimum host.
- [ ] Exact immutable public CLI tag and commit passed HTTP and proxied-HTTPS compatibility against candidate-backed origins without an insecure transport override.
- [ ] Live qualification run/attempt, exact five successful jobs, final artifact ID/archive digest, downloaded record bytes, and all eight check hashes were independently verified.
- [ ] Release notes name predecessor (`none` for the initial release), successor digest, CLI tag, data/config changes, irreversible migrations, and rollback boundary.

## Authorization and promotion

- [ ] `docs/releases/PUBLICATION_BLOCKED.md` removed in a separately reviewed authorization change.
- [ ] Public evidence manifest contains only approved redacted fields, including the release-maintainer `preauthorization`, and matches all restricted evidence hashes.
- [ ] `bin/release-validate --mode publish` passed for the exact tag, SHA, and manifest digest.
- [ ] A required reviewer approved the protected `source-release` environment; this distinct runtime approval is not inferred from `preauthorization`.
- [ ] Redacted `environment-approval.json` binds the exact repository, source/authorizing SHAs, workflow run/attempt, and canonical review digest without reviewer identity or comment.
- [ ] Existing partial tag/image/attestation/release objects were absent or matched exactly before resumable promotion.
- [ ] Immutable release and its exact approval/evidence/qualification/provenance/SBOM assets, manifest digest, and adjacent upgrade/rollback documents verified after publication.
