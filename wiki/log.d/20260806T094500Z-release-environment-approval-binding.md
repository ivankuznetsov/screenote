## [2026-08-06] Bind publication to protected-environment review history

**Action:** Distinguished committed release-maintainer preauthorization from
GitHub's runtime protected-environment approval. Promotion now records a
redacted approval artifact from exactly one approved `source-release` review,
and exact resumptions revalidate the immutable artifact against the historical
workflow attempt and current review history. Candidate and historical workflow
identities require GitHub's ref-qualified workflow path on the default branch.

**Pages updated:** wiki/self-hosting.md, wiki/gaps.md,
wiki/log.d/20260806T094500Z-release-environment-approval-binding.md, wiki/log.md

**Source:** `.github/workflows/release.yml`, `bin/release-validate`, release
evidence documentation, and executable release artifact contracts
