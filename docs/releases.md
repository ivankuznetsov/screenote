# Screenote releases

Screenote releases are source-available source tags plus one digest-addressed, multi-platform GHCR image built from the same protected default-branch commit. A release is not authorized merely because tests pass or a maintainer can create a tag.

The first publication is deliberately blocked by [`docs/releases/PUBLICATION_BLOCKED.md`](releases/PUBLICATION_BLOCKED.md). Removing that file is a separately reviewed release change after every external gate below has real evidence.

## Release identity

- Release tags use `vMAJOR.MINOR.PATCH` with no mutable prerelease alias as an operational input.
- The OCI manifest digest is the canonical image identity. Compose, upgrade, and rollback instructions use `ghcr.io/ivankuznetsov/screenote@sha256:…`, never `latest`.
- Each server release names an exact tested public CLI tag.
- The initial release declares predecessor `none`. Every later release names exactly one immediately supported predecessor and both immutable image digests.
- Upgrades are sequential. Skipping releases is unsupported.

## Gate order

1. Freeze repository writes and record the exact protected `main` commit.
2. Complete legal approval of chain of title, the O'Saasy text and notice, third-party notices, and the candidate public history.
3. Audit every branch and tag plus repository-adjacent Actions logs and artifacts, issues, pull requests, wiki pages, releases, packages, and Pages output.
4. Run GitGuardian's history-aware GitHub App scan and the trusted `ggshield` full-history and current-tree scans. The workflow pins the canonical GitGuardian instance and exact reviewed configuration path so repository or runner defaults cannot redirect or weaken the scan. Review every incident. Confirmed credentials are revoked or rotated before resolution; ignores require a documented false positive or incapable test value.
5. Build AMD64 and ARM64 OCI layouts once from the exact commit. Import those retained bytes into the trusted scanner runtime, verify their config/layer digests, scan both with `ggshield` and a checksum-pinned Trivy whose nonzero finding/error exit and schema-v2 report both fail closed, and generate the SBOM and provenance inputs. Trivy receives explicit empty trusted config/ignore files and reports suppressed findings; Syft receives an explicit empty trusted config, preventing repository or runner auto-configuration from suppressing vulnerability or package inventory.
6. Treat the protected-main CI matrix as source-contract evidence only. Run `.github/workflows/release-qualification.yml` separately against the retained candidate bytes and immutable CLI tag. It must produce the exact native AMD64/ARM64 self-hosted and SaaS boot, minimum-host backup/restore and SQLite load, and HTTP/HTTPS CLI records.
7. Independently inspect the installed main/tag rulesets, GitGuardian App check source, incident-check configuration, protected `source-release` environment, GHCR permissions, and GitHub immutable-release setting.
8. A release maintainer approves the protected environment. Promotion copies the retained layouts without rebuilding, verifies every existing partial object before resuming, creates the protected tag, attests the manifest digest, and creates one immutable GitHub release.

Pending, unavailable, skipped, malformed, expired, or mismatched evidence fails closed. A partial tag, image, attestation, or release is reusable only when it exactly matches the approved commit and retained digests; otherwise publication stops for investigation.

## Prepare and validate

Static repository preparation is safe to run before external authorization:

```sh
bin/release-validate --mode prepare
```

The publication check requires the tracked blocker to be removed and an exact redacted evidence document:

```sh
bin/release-validate \
  --mode publish \
  --evidence docs/releases/evidence/public-evidence.json \
  --source-sha "$(git rev-parse HEAD)" \
  --tag v1.0.0 \
  --qualification-run-id 123456789 \
  --qualification-artifact-sha256 <64-lowercase-hex>
```

Never put restricted evidence in the repository or a public workflow artifact. See [security evidence](releases/security-evidence.md), the [publication checklist](releases/publication-checklist.md), and the [initial release notes](releases/initial-release.md).

## Retained candidate and promotion workflow

`.github/workflows/release.yml` has two manually selected operations. `candidate` accepts a full commit and semantic tag only when the commit is the current protected default-branch head. It performs the source/history gates before building, builds one retained AMD64/ARM64 OCI layout, verifies imported manifest and configuration digests, runs exact-image secret and Critical/High vulnerability scans, generates platform SBOMs and provenance input, and uploads one 30-day candidate bundle. It creates no tag, registry object, attestation, or release.

`.github/workflows/release-qualification.yml` is the distinct release-only runtime gate. It accepts the exact candidate run and bundle hash, an immutable staging reference ending in that candidate's manifest digest, and an immutable CLI tag. It verifies the candidate run and artifact live, resolves the CLI tag to one commit, and uses separately configured native runner labels. Its final artifact contains eight exact redacted check records: self-hosted and SaaS boot on each architecture, backup/restore and SQLite load on the documented minimum host, and public CLI compatibility over HTTP and HTTPS. The workflow fails before emitting evidence when the native runners, minimum-host profile, tracked load driver, tracked CLI contract driver, or candidate-backed origins are not configured. PR jobs named `public-cli`, `container-local`, or `backup-restore` remain contract checks and never substitute for this qualification.

`publish` accepts the exact successful candidate run/bundle hash and exact successful qualification run/artifact digest. Exactly one direct-parent authorizing commit may follow the built source commit; it may alter only the publication blocker, final redacted evidence, and final release notes. Any intervening or merge commit requires a new candidate, preventing a forbidden path or earlier secret-bearing revision from disappearing in a net diff. Authorization live-fetches the selected qualification attempt and its exact five successful jobs, resolves the one final artifact by ID, downloads and verifies its record/check bytes, re-resolves the CLI tag, and compares every source/candidate/manifest/platform/check binding with committed public evidence. Hash-shaped strings alone cannot authorize publication. Validation also binds labels, SBOM, provenance, scanner evidence, rulesets, approvals, and a release-maintainer `preauthorization` record. That committed record names `source-release` only as the intended promotion environment; it is not proof that GitHub's protected-environment review occurred. The final release-note, public-evidence, and qualification-record bytes are scanned with checksum-pinned `ggshield` before the one-day same-run promotion artifact is retained.

The promotion job deliberately performs no checkout and executes no repository code. Its first post-environment step reads GitHub's review history for the current run and fails closed unless it contains exactly one approved review covering exactly `source-release`. It writes a redacted `environment-approval.json` that binds the repository, source and authorizing SHAs, workflow run ID and attempt, environment and state, plus a SHA-256 of the complete review object in recursively key-sorted compact JSON. Reviewer identity and comment are included only in that digest, never in the record. The next step refreshes the exact GitGuardian repository source and every incident page; missing credentials, malformed/unavailable state, or any open incident stops before release-token creation, downloads, third-party Actions, or writes.

Promotion then classifies the image, source tag, GitHub attestation, and release as absent or exact and permits only a strict completed-prefix state. An exact prefix is resumed; a duplicate attestation, out-of-order partial state, ambiguous lookup, mismatch, or non-404 lookup error stops without writing. If the exact immutable release already exists, promotion downloads its `environment-approval.json`, validates its current repository/source/authorizing bindings, validates its named historical workflow attempt and current approval history through GitHub's API, and uses those immutable bytes for release-asset comparison. The attestation signs the retained `provenance.json` under Screenote's stable HTTPS predicate type: its certificate is bound to the authorizing workflow SHA, while the decoded signed predicate is compared structurally to the candidate's built source SHA, tag, repository, and run identity. An unconditional final pass re-verifies all four remote objects and every exact release asset, including the approval record. See [release dependency pins](releases/action-pins.md) for every Action and downloaded tool digest.

The protected environment must define `SCREENOTE_RELEASE_APP_CLIENT_ID` and `SCREENOTE_RELEASE_APP_PRIVATE_KEY` for the dedicated release App. Its installation needs repository Administration read, Contents write, and Packages write permissions: promotion uses Administration read only to prove that immutable releases are still enabled immediately before the first publication mutation. Candidate scans use `GITGUARDIAN_API_KEY`; the separate metadata-only incident workflow uses `GITGUARDIAN_INCIDENTS_API_KEY` and `GITGUARDIAN_SOURCE_ID`, plus optional `GITGUARDIAN_API_URL` for GitGuardian's documented US or EU API origin. These are external configuration requirements, never repository defaults.

Qualification additionally requires repository variables `SCREENOTE_RELEASE_AMD64_RUNNER_LABEL`, `SCREENOTE_RELEASE_ARM64_RUNNER_LABEL`, `SCREENOTE_RELEASE_MINIMUM_HOST_RUNNER_LABEL`, and a versioned `SCREENOTE_RELEASE_MINIMUM_HOST_PROFILE`; the three labels must select ephemeral trusted native runners. `SCREENOTE_RELEASE_LOAD_DRIVER_PATH` must name a tracked executable in the exact server commit. `SCREENOTE_PUBLIC_CLI_CONTRACT_PATH` must name a tracked executable in the exact CLI tag, while `SCREENOTE_PUBLIC_CLI_HTTP_ORIGIN` and `SCREENOTE_PUBLIC_CLI_HTTPS_ORIGIN` must name distinct candidate-backed origins controlled by that driver. Missing, untracked, non-executable, emulated, moving-tag, or non-candidate configuration prevents the final qualification artifact from being created.

## Protection configuration

The checked-in files under `.github/rulesets/` are reviewed templates, not proof of live protection. Before applying them, replace every sentinel integration ID with the actual installed GitHub App ID, verify the expected check name and App source through the GitHub API, and record the returned ruleset IDs and hashes in restricted evidence. Export the installed rulesets, canonicalize them, and bind their hashes into the public evidence manifest.

The required GitGuardian controls are deliberately split:

- The GitGuardian GitHub App owns history-aware pull-request checks. Its skip actions must be disabled and its exact check source must be required by the main ruleset.
- `.github/workflows/secrets.yml` performs a separate metadata-only query of every incident page for the configured repository source. It checks out no code and treats missing credentials, API errors, unknown response shapes, unsafe pagination links, or any `TRIGGERED`/`ASSIGNED` incident as failure. Because `pull_request_target` executes against the trusted base revision, it first replaces any old result with the named `pending` status on the validated PR head and test-merge SHAs, then publishes `success` only after every page closes or `error` on failure. If error publication itself fails, the latest pending result remains blocking. Promotion independently runs the same strict live API policy immediately after it binds the protected-environment review.
- The metadata-only check also requires `monitoring_status` to equal `active` and rejects archived or deleted provider metadata. It deliberately leaves proof of a completed historical scan to the separately retained GitGuardian App/source-scan evidence; neither check substitutes for the other.
- Trusted candidate jobs pin `GITGUARDIAN_INSTANCE` and the exact reviewed `.gitguardian.yaml` through `--config-path`, which disables local/global auto-discovery, and run `ggshield` without `--exit-zero`, `--ignore-known-secrets`, ignored matches, ignored paths, or ignored detectors.

GitGuardian's official integration performs historical scanning when a GitHub source is connected: <https://docs.gitguardian.com/internal-monitoring/integrate-sources/vcs-integrations/github>. Its API uses cursor pagination through `Link` headers: <https://docs.gitguardian.com/api-docs/pagination>. GitHub's official documentation covers [workflow-run approval history](https://docs.github.com/en/rest/actions/workflow-runs#get-the-review-history-for-a-workflow-run), [rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets), [secure Actions use](https://docs.github.com/en/actions/reference/security/secure-use), [artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations), and [immutable releases](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes).

## Incident after publication

A suspected credential immediately blocks new default-branch updates, tags, images, and releases. Revoke or rotate confirmed credentials, determine affected revisions and artifacts, close the GitGuardian incident only under the disposition rules above, and repeat the exact-revision gates before resuming. If a secret cannot be revoked, protected/confidential data or third-party IP is present, or history retention lacks security and legal approval, publish only after a reviewed history rewrite or clean public root.
