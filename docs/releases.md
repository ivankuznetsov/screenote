# Screenote releases

Screenote releases are source-available source tags plus one digest-addressed,
multi-platform GHCR image built from the same protected default-branch commit.
A tag is publishable only after the automated checks and retained ONCE
self-hosting drills below pass.

The first publication is held by the technical sentinel [`docs/releases/PUBLICATION_BLOCKED.md`](releases/PUBLICATION_BLOCKED.md). Remove it only when the repository and release infrastructure are ready; the protected `source-release` environment remains the actual human authorization at promotion time.

## Release identity

- Release tags use immutable `vMAJOR.MINOR.PATCH` names.
- The OCI manifest digest is the canonical release identity. Release notes
  record the readable tag and digest together, and promotion points the public
  `latest` channel at those exact bytes. Local rebuilds are not release inputs.
- Each server release names one exact tested public CLI tag.
- The first release declares predecessor `none`; later release evidence records
  the immediate predecessor used for rollback qualification.
- Every new release must upgrade directly from every earlier published
  Screenote release, so the public `latest` channel never requires an operator
  to select intermediate images.

## Gate order

1. Freeze the exact protected `main` commit.
2. Run the GitGuardian App history check, trusted `ggshield` full-history/current-tree scans, and live incident query. Open or unknown incidents fail closed.
3. Build AMD64 and ARM64 OCI layouts once. Verify imported config/layer digests, scan both layouts with GitGuardian and checksum-pinned Trivy, and generate platform SBOMs plus provenance input.
4. Treat protected-main CI as source and container/ONCE contract evidence only.
   Run `.github/workflows/release-qualification.yml` against the retained
   candidate bytes and immutable CLI tag for native AMD64/ARM64 boots. The
   exact-image SaaS boots receive four role-specific database URLs and verify
   them through Active Record without requiring an adapter name or server
   version. The remaining checks cover minimum-host backup/restore and SQLite
   load plus HTTP/HTTPS CLI compatibility.
5. Retain an end-to-end Linux deployment of the exact `tag@digest` image
   through the supported ONCE stable release named in the evidence, ONCE's
   Kamal Proxy, and Thruster with Screenote automatic updates disabled,
   including remote digest and label checks, the exact proxy manifest digest,
   HTTPS, hostile-header and direct-sibling client-IP spoof rejection, restart,
   and persistence evidence.
6. Publish the release-matched ONCE backup and restore commands, then retain a
   restore drill covering all four SQLite roles and local screenshot storage;
   for S3 mode, retain matching provider recovery evidence as well.
   Successor releases repeat the update and restore drill from every earlier
   published release.
7. Verify live main/tag rulesets, the GitGuardian App check source, the protected `source-release` environment, GHCR permissions, and immutable GitHub releases.
8. Validate the technical public evidence manifest against the exact candidate and qualification artifacts.
9. Approve the protected `source-release` environment. Promotion rechecks live incidents, verifies every remote object is absent or an exact resumable prefix, then publishes the image, tag, provenance attestation, and immutable release before pointing `latest` at that exact manifest.

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

`.github/workflows/release-qualification.yml` is the separate release-only runtime gate. It uses configured native runner labels and the tracked `config/release/minimum-host-v1.json` profile from the exact qualification commit. The SQLite driver emits the `screenote-load-smoke/v2` evidence contract, including the profile identity and measured latency, queue, lock, reconciliation, integrity, and request outcomes. The workflow hashes those file bytes into its final artifact, which contains exactly eight checks: self-hosted and SaaS boot on AMD64 and ARM64, backup/restore, SQLite load, and public CLI behavior over HTTP and HTTPS. Each SaaS boot still qualifies the exact retained image through its production entrypoint, but its primary, cache, queue, and cable connections are supplied as URLs and exercised through Active Record; qualification records no database adapter or server-version requirement. The hosted Kamal configuration supplies those role URLs without turning its runtime choice into an application, CI, or release-qualification constraint. Pull-request jobs with similar names are contract checks and never substitute for qualification.

The ONCE/Kamal Proxy/Thruster deployment drill and ONCE backup/restore drill
are still sentinel-tracked retained gates, not two of those eight
qualification checks. Publication remains blocked until their evidence is
automated, bound to the exact candidate, and validated by the promotion path.

The published image includes the `service=screenote` release-identity label,
serves port 80, exposes `/up`, and persists state below `/storage` (also mounted
by ONCE at `/rails/storage`). Promotion publishes the already qualified parent
manifest without changing its digest. Ordinary development or custom source
builds carry no supported-release artifact claim.

The promotion job performs no checkout and executes no repository code. It is gated by the protected `source-release` environment and verifies the current workflow run has exactly one approved review for that environment. It publishes no approval record. Scanner details stay in job-private diagnostics; public release assets contain only technical manifests and hashes.

Promotion classifies the image, source tag, GitHub provenance attestation, and release as absent or exact. Only a completed prefix is resumable. Existing mismatched, duplicated, ambiguous, or out-of-order objects stop publication. The final step re-verifies the tag, manifest, signed provenance predicate, immutable release body, and every exact asset.

See [release dependency pins](releases/action-pins.md) for every Action and downloaded tool digest.

## External configuration

The `source-release` environment defines `SCREENOTE_RELEASE_APP_CLIENT_ID` and `SCREENOTE_RELEASE_APP_PRIVATE_KEY` for a dedicated GitHub App with repository Administration read, Contents write, and Packages write permissions. Candidate scans use `GITGUARDIAN_API_KEY`; incident checks use `GITGUARDIAN_INCIDENTS_API_KEY` and `GITGUARDIAN_SOURCE_ID`, with optional `GITGUARDIAN_API_URL` for the documented GitGuardian US or EU API origin.

Qualification requires these repository variables:

- `SCREENOTE_RELEASE_AMD64_RUNNER_LABEL`
- `SCREENOTE_RELEASE_ARM64_RUNNER_LABEL`
- `SCREENOTE_RELEASE_MINIMUM_HOST_RUNNER_LABEL`
- `SCREENOTE_PUBLIC_CLI_CONTRACT_PATH`
- `SCREENOTE_PUBLIC_CLI_HTTP_ORIGIN`
- `SCREENOTE_PUBLIC_CLI_HTTPS_ORIGIN`

The runner labels select ephemeral trusted native runners. The minimum-host profile and server load driver are fixed by the exact server commit rather than repository variables. The public-CLI driver must be a tracked executable in the exact CLI commit, and the HTTP/HTTPS origins must be distinct candidate-backed endpoints.

## Protection configuration

The files under `.github/rulesets/` are templates, not proof of live protection. Replace sentinel integration IDs with the installed GitHub App IDs, apply all three rulesets, export the installed settings through GitHub's API, and bind their canonical hashes into technical release evidence.

GitGuardian controls remain deliberately independent:

- The GitGuardian GitHub App owns history-aware pull-request checks; skip actions must be disabled and its exact App check must be required by the main ruleset.
- `.github/workflows/secrets.yml` performs a metadata-only, paginated live incident query without checking out pull-request code. Missing credentials, API errors, unknown states, unsafe pagination, archived/deleted source metadata, or any `TRIGGERED`/`ASSIGNED` incident fail closed.
- Candidate jobs run checksum-pinned `ggshield` against the exact source history/current tree and imported platform images with the reviewed `.gitguardian.yaml`. They do not use status-discarding or ignore options.

## Incident after publication

A suspected credential blocks new tags, images, and releases until investigated. Revoke or rotate a confirmed credential, resolve the GitGuardian incident only after remediation, determine which revisions and artifacts were affected, and rerun the exact-revision gates before resuming publication.
