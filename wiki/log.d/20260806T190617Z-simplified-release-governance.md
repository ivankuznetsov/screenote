## [2026-08-06] Simplify source-release governance

**Action:** Removed legal, ownership, manual repository-history, unused encrypted-credential inventory, and committed preauthorization records from the source-release contract. Public evidence v2 now contains only technical build, scan, ruleset, CI, qualification, and artifact bindings. The protected `source-release` environment remains the live human gate, while GitGuardian history/current-tree/image scans, live incidents, vulnerability policy, exact qualification, SBOM, provenance, immutable objects, and final readback remain fail closed. This supersedes earlier changelog entries that described restricted evidence, credential-history disposition, committed preauthorization, or a published environment-approval record as publication requirements.

**Pages updated:** wiki/self-hosting.md, wiki/gaps.md, wiki/plans-and-initiatives.md, wiki/log.d/20260806T190617Z-simplified-release-governance.md, wiki/log.md

**Source:** `bin/release-validate`, `.github/workflows/release.yml`, release evidence fixtures/contracts, and `docs/releases*.md`
