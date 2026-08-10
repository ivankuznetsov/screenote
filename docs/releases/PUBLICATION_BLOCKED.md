# Publication is blocked

This file is an executable release-readiness sentinel. While it exists, `bin/release-validate --mode publish` and `.github/workflows/release.yml` must stop before creating a tag, image, provenance attestation, or GitHub release.

Remove it when all technical prerequisites are ready:

- GitGuardian's App history scan, explicit full-history/current-tree scans, and live incident checks pass for the candidate commit.
- Main and release-tag rulesets, the exact GitGuardian App check, protected `source-release` environment, immutable GitHub releases, and GHCR permissions are configured and verified.
- The canonical public CLI has an immutable tested tag.
- Exact AMD64/ARM64 layouts, manifest digest, SBOM, provenance, secret/vulnerability scans, source-contract checks, and public-log scan match the candidate.
- Native AMD64/ARM64/minimum-host qualification runners, the tracked public-CLI driver, and candidate-backed HTTP/HTTPS origins are configured; qualification uses the profile and load driver fixed by the exact server commit.
- The retained qualification artifact proves all eight required runtime checks; pull-request contract jobs are not substitutes.
- Its two exact-image SaaS boot checks exercise separate primary, cache, queue,
  and cable URLs through Active Record without binding qualification to a
  database adapter or server version.
- The exact `tag@digest` image has completed a retained Linux deployment
  through the supported released stock ONCE version named in the evidence.
  The drill installs ONCE with
  `curl https://get.once.com | ONCE_INTERACTIVE=false sh`, then uses
  `once deploy` with an explicit host and matching HTTPS
  `SCREENOTE_BASE_URL`. Retain ONCE's Kamal Proxy and Thruster, automatic
  application updates, the atomic first-visitor administrator claim, remote
  digest/label identity, the exact proxy manifest digest, HTTPS and client-IP
  forwarding, hostile-header and direct-sibling spoof rejection, restart,
  volume persistence, and a bare `once update HOST` exercise.
- ONCE backup and restore commands are published and a retained drill proves
  recovery of all four SQLite roles plus local files using the exact release
  image; S3 mode also proves recovery of the matching external namespace.
- Promotion proves that the public `latest` channel resolves to the exact
  manifest of the newest immutable GitHub Release.

Deleting this file records technical readiness only. Promotion still requires the protected `source-release` environment approval and every exact validator must pass.
