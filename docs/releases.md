# Screenote releases

Screenote releases are source-available source tags plus one digest-addressed, multi-platform GHCR image built from the same protected default-branch commit. A tag is publishable only after the automated source, image, compatibility, and repository-protection checks below pass.

The first publication is held by the technical sentinel [`docs/releases/PUBLICATION_BLOCKED.md`](releases/PUBLICATION_BLOCKED.md). Remove it only when the repository and release infrastructure are ready; the protected `source-release` environment remains the actual human authorization at promotion time.

## Release identity

- Release tags use immutable `vMAJOR.MINOR.PATCH` names.
- The OCI manifest digest is the canonical image identity. Operator instructions use `ghcr.io/ivankuznetsov/screenote@sha256:…`, never `latest`.
- Each server release names one exact tested public CLI tag.
- The first release declares predecessor `none`; later releases name the one immediately supported predecessor.
- Upgrades are sequential. Skipping releases is unsupported.

## Gate order

1. Freeze the exact protected `main` commit.
2. Run the GitGuardian App history check, trusted `ggshield` full-history/current-tree scans, and live incident query. Open or unknown incidents fail closed.
3. Build AMD64 and ARM64 OCI layouts once. Verify imported config/layer digests, scan both layouts with GitGuardian and checksum-pinned Trivy, and generate platform SBOMs plus provenance input.
4. Treat protected-main CI as source-contract evidence only. Run `.github/workflows/release-qualification.yml` against the retained candidate bytes and immutable CLI tag for native AMD64/ARM64 boots, minimum-host backup/restore and SQLite load, and HTTP/HTTPS CLI compatibility.
5. Verify live main/tag rulesets, the GitGuardian App check source, the protected `source-release` environment, GHCR permissions, and immutable GitHub releases.
6. Validate the technical public evidence manifest against the exact candidate and qualification artifacts.
7. Approve the protected `source-release` environment. Promotion rechecks live incidents, verifies every remote object is absent or an exact resumable prefix, then publishes the image, tag, provenance attestation, and immutable release.

Missing, skipped, malformed, expired, or mismatched technical evidence fails closed. A partial tag, image, attestation, or release is reusable only when it exactly matches the candidate commit and retained digests.

## Prepare and validate

Static preparation is safe before external services are configured:

```sh
bin/release-validate --mode prepare
```

The publication check requires the sentinel to be removed and a completed v2 technical evidence document:

```sh
bin/release-validate \
  --mode publish \
  --evidence docs/releases/evidence/public-evidence.json \
  --source-sha "$(git rev-parse HEAD)" \
  --tag v1.0.0 \
  --qualification-run-id 123456789 \
  --qualification-artifact-sha256 <64-lowercase-hex>
```

See [technical release evidence](releases/security-evidence.md), the [publication checklist](releases/publication-checklist.md), and the [initial release notes](releases/initial-release.md).

## Candidate, qualification, and promotion

`.github/workflows/release.yml` exposes two manual operations:

- `candidate` accepts a full commit and semantic tag only when the commit is the current protected default-branch head. It runs source/history checks, builds one retained AMD64/ARM64 layout, scans the imported bytes, and uploads the candidate bundle for 30 days. It creates no public object.
- `publish` accepts the exact successful candidate run/bundle hash and exact successful qualification run/artifact hash. One direct-parent release-metadata commit may delete the sentinel, add final technical evidence, and finalize release notes; any other path or commit shape requires a new candidate. The job verifies those bytes, the live qualification run and its eight checks, the current CLI tag, the candidate manifest, SBOMs, provenance, scanner results, and ruleset evidence before retaining a one-day promotion input.

`.github/workflows/release-qualification.yml` is the separate release-only runtime gate. It uses configured native runner labels and a versioned minimum-host profile. Its final artifact contains exactly eight checks: self-hosted and SaaS boot on AMD64 and ARM64, backup/restore, SQLite load, and public CLI behavior over HTTP and HTTPS. Pull-request jobs with similar names are contract checks and never substitute for qualification.

The promotion job performs no checkout and executes no repository code. It is gated by the protected `source-release` environment and verifies the current workflow run has exactly one approved review for that environment. It publishes no approval record. Scanner details stay in job-private diagnostics; public release assets contain only technical manifests and hashes.

Promotion classifies the image, source tag, GitHub provenance attestation, and release as absent or exact. Only a completed prefix is resumable. Existing mismatched, duplicated, ambiguous, or out-of-order objects stop publication. The final step re-verifies the tag, manifest, signed provenance predicate, immutable release body, and every exact asset.

See [release dependency pins](releases/action-pins.md) for every Action and downloaded tool digest.

## External configuration

The `source-release` environment defines `SCREENOTE_RELEASE_APP_CLIENT_ID` and `SCREENOTE_RELEASE_APP_PRIVATE_KEY` for a dedicated GitHub App with repository Administration read, Contents write, and Packages write permissions. Candidate scans use `GITGUARDIAN_API_KEY`; incident checks use `GITGUARDIAN_INCIDENTS_API_KEY` and `GITGUARDIAN_SOURCE_ID`, with optional `GITGUARDIAN_API_URL` for the documented GitGuardian US or EU API origin.

Qualification requires these repository variables:

- `SCREENOTE_RELEASE_AMD64_RUNNER_LABEL`
- `SCREENOTE_RELEASE_ARM64_RUNNER_LABEL`
- `SCREENOTE_RELEASE_MINIMUM_HOST_RUNNER_LABEL`
- `SCREENOTE_RELEASE_MINIMUM_HOST_PROFILE`
- `SCREENOTE_RELEASE_LOAD_DRIVER_PATH`
- `SCREENOTE_PUBLIC_CLI_CONTRACT_PATH`
- `SCREENOTE_PUBLIC_CLI_HTTP_ORIGIN`
- `SCREENOTE_PUBLIC_CLI_HTTPS_ORIGIN`

The runner labels select ephemeral trusted native runners. Driver paths must be tracked executables in the exact server or CLI commit, and the HTTP/HTTPS origins must be distinct candidate-backed endpoints.

## Protection configuration

The files under `.github/rulesets/` are templates, not proof of live protection. Replace sentinel integration IDs with the installed GitHub App IDs, apply all three rulesets, export the installed settings through GitHub's API, and bind their canonical hashes into technical release evidence.

GitGuardian controls remain deliberately independent:

- The GitGuardian GitHub App owns history-aware pull-request checks; skip actions must be disabled and its exact App check must be required by the main ruleset.
- `.github/workflows/secrets.yml` performs a metadata-only, paginated live incident query without checking out pull-request code. Missing credentials, API errors, unknown states, unsafe pagination, archived/deleted source metadata, or any `TRIGGERED`/`ASSIGNED` incident fail closed.
- Candidate jobs run checksum-pinned `ggshield` against the exact source history/current tree and imported platform images with the reviewed `.gitguardian.yaml`. They do not use status-discarding or ignore options.

## Incident after publication

A suspected credential blocks new tags, images, and releases until investigated. Revoke or rotate a confirmed credential, resolve the GitGuardian incident only after remediation, determine which revisions and artifacts were affected, and rerun the exact-revision gates before resuming publication.
