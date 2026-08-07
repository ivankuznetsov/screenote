# Publication is blocked

This file is an executable release-readiness sentinel. While it exists, `bin/release-validate --mode publish` and `.github/workflows/release.yml` must stop before creating a tag, image, provenance attestation, or GitHub release.

Remove it when all technical prerequisites are ready:

- GitGuardian's App history scan, explicit full-history/current-tree scans, and live incident checks pass for the candidate commit.
- Main and release-tag rulesets, the exact GitGuardian App check, protected `source-release` environment, immutable GitHub releases, and GHCR permissions are configured and verified.
- The canonical public CLI has an immutable tested tag.
- Exact AMD64/ARM64 layouts, manifest digest, SBOM, provenance, secret/vulnerability scans, source-contract checks, and public-log scan match the candidate.
- Native AMD64/ARM64/minimum-host qualification runners, the tracked public-CLI driver, and candidate-backed HTTP/HTTPS origins are configured; qualification uses the profile and load driver fixed by the exact server commit.
- The retained qualification artifact proves all eight required runtime checks; pull-request contract jobs are not substitutes.

Deleting this file records technical readiness only. Promotion still requires the protected `source-release` environment approval and every exact validator must pass.
