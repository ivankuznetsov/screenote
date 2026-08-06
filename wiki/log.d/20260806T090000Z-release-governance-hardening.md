---
title: Release governance hardening
type: changelog
created: 2026-08-06
tags: [release, security, supply-chain, governance]
---

- Candidate archive preflight now parses the actual retained tar with
  `Gem::Package::TarReader` and permits only safe relative regular-file and
  directory members. Traversal paths, symlinks, hardlinks, devices, FIFOs, and
  other unsupported member types fail before extraction.
- The ORAS 1.3.2 registry preflight classifies an image as absent only for its
  exact requested-reference `failed to find ... not found` response or a
  single-line, anchored `manifest unknown` response. Ambiguous 404s, generic
  `not found` text, unrelated errors, and trailing output remain fatal.
- Publication authorization is exactly one direct-parent commit after the built
  source revision, with the exact path/status tuple: delete
  `docs/releases/PUBLICATION_BLOCKED.md`, add
  `docs/releases/evidence/public-evidence.json`, and modify
  `docs/releases/initial-release.md`; no additional changes are accepted.
- Both the workflow and `bin/release-validate` treat a dangling symlink at the
  publication-sentinel path as present, preserving the fail-closed blocker.
- The promotion job's default token is limited to `contents: read`,
  `attestations: write`, and `id-token: write`; repository and package mutation
  remains isolated to the dedicated release App token.
- `THIRD_PARTY_NOTICES.md` now matches the locked Thruster 0.1.23 dependency
  and the Alpine packages installed by `Dockerfile` through `apk`.

Publication remains externally blocked pending legal and Future Spin Ltd
chain-of-title approval; credential inventory, rotation, revocation, and history
disposition; live GitGuardian evidence; GitHub ruleset and protected-environment
configuration; an immutable public CLI tag; and retained exact-candidate image,
scan, SBOM, provenance, and release-note evidence. The publication sentinel must
remain until those gates are complete.

Related: [[self-hosting]], [[testing-and-ci]], [[gaps]].
