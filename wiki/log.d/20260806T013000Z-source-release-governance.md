---
title: Source release governance and publication gates
type: changelog
created: 2026-08-06
tags: [source-available, release, security, gitguardian, supply-chain]
---

- Added the exact adapted O'Saasy license and Future Spin Ltd notice plus contributor, security, support, third-party, self-hosting, and release documentation.
- Removed encrypted Rails credentials from the current publication tree, ignored future encrypted payloads and keys, and recorded that authorized inventory, rotation, and history disposition are still blocking gates.
- Split the history-aware GitGuardian App, metadata-only paginated repository-incident check, and trusted source/image `ggshield` scans so none substitutes for another; the trusted incident gate explicitly reports to the PR head/test-merge SHA instead of relying on `pull_request_target`'s base-SHA check.
- Added no-bypass main/tag ruleset templates, full-SHA Action pins with provenance, checksum-pinned release tools, Dependabot coverage, redacted/restricted evidence contracts, and an executable publication sentinel.
- Added retained candidate and no-checkout protected promotion stages with exact source, OCI digest, SBOM, provenance, evidence, final-note, partial-object, and post-create readback bindings.
- Added offline adversarial incident-pagination tests and positive/negative artifact-contract fixtures; publication remains blocked on the documented external legal, credential, GitGuardian, repository-setting, CLI, and exact-candidate evidence.
