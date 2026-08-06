# Restricted release evidence record

Do not commit a completed copy of this template and do not upload it as a public Action artifact. Store it in the approved restricted evidence system with encryption, access logging, named owners, a retention/deletion date, and an incident deletion hold.

## Identity

- Exact repository/source SHA:
- Release tag and predecessor:
- OCI platform and manifest digests:
- Restricted-record opaque ID:
- Finalized record SHA-256:
- Created/updated timestamps:
- Access owners:
- Retain until / delete after:

## Legal and source review

- Chain-of-title record:
- O'Saasy text/notice approval:
- Contribution authority:
- Dependency/base-image/vendored-asset notices:
- History retention or rewrite decision:
- Protected/confidential data and third-party IP review:

## Credential inventory

Inventory provider, environment, owner, status, rotation/revocation time, and provider evidence. Keep actual values out of this record whenever an opaque provider ID is sufficient. Never copy values to public evidence.

## GitGuardian incidents

Record every relevant incident's restricted identifier, source, detector, occurrence scope, validity, disposition, remediation proof, and authorized resolver/ignorer. A confirmed credential must have revocation/rotation proof before resolution. An ignore requires false-positive or incapable-test-value proof.

## Vulnerabilities and waivers

Retain raw scanner results privately. A waiver names one finding hash, severity, exact platform digest, security approver role, approval time, expiry no later than 30 days, exploitability analysis, compensating control, and follow-up owner. Broad or anonymous waivers are invalid.

## Repository-adjacent surfaces

Record branches, tags, refs, Actions logs/artifacts/caches, issues, pull requests, wiki, releases, packages, Pages, forks/mirrors, and any provider-side retained copies. Record the final write-freeze inventory hashes.

## Exact-artifact verification

Record OCI-layout config/layer digests before and after trusted import, source/image secret scans, vulnerability database and policy versions, SBOM/provenance hashes, and source-contract conclusions. Separately record the exact qualification workflow run/attempt and artifact receipt, native runner identities, minimum-host profile, retained-image boot evidence for both editions and architectures, load evidence, same-image backup/restore evidence, immutable CLI tag/commit/binary identity, HTTP/HTTPS candidate-origin evidence, and public-log sentinel scan. Never promote PR contract jobs into release-qualification claims.

## Final approvals

- Legal approver role / opaque approval ID:
- Security approver role / opaque approval ID:
- Repository/ruleset reviewer role / opaque approval ID:
- Release preauthorization role / opaque approval ID:
- GitHub protected-environment reviewer, comment, run ID/attempt, and retained API response:
- Public `environment-approval.json` SHA-256:
- Final disposition and timestamp:
