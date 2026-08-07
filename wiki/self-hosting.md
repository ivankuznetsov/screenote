---
title: Self-Hosted Distribution
type: initiative
source: docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md
created: 2026-08-05
updated: 2026-08-07
tags: [self-hosting, kamal, docker, licensing, storage, release]
---

# Self-Hosted Distribution

**TLDR:** Screenote implements a source-available, single-server self-hosted edition alongside `screenote.ai`. The public installation path is now Kamal plus Kamal Proxy, following the Rails-style deployment used by Fizzy; publication remains gated by the release controls below.

## Distribution Model

- Future Spin Ltd will publish Screenote under the O'Saasy license.
- One public repository will carry the shared core and an explicitly enabled SaaS capability.
- Tagged releases will provide a prebuilt container image after quality, security, migration, and self-hosted smoke gates pass.
- The production image starts from a digest-pinned Ruby 3.4.10 Alpine 3.24 multi-architecture index. Transitional Go CLI sources are not copied into the Rails runtime image, so its SBOM and vulnerability gate describe shipped runtime software rather than separately tested source.
- Public language should use “source-available and self-hostable” because O'Saasy restricts directly competing hosted services.

## Public Onboarding

The repository README leads with the three-step publish, review, and feedback
loop, then separates hosted use from self-hosted operation. Team setup is
presented as one-time instance claim, project creation, and invitation-based
admission; advanced storage, provider, backup, and upgrade details remain in
the operator guide.

Until the first release exists, the README labels deployment from the
repository as a development preview. A supported install clones the exact tag
named by a GitHub release into a deployment branch; cloning the moving default
branch remains preview-only. The copyable path then edits the tracked
`config/deploy.yml` starter, populates ignored `.kamal/secrets`, runs
`bin/kamal setup`, claims `/bootstrap`, and uses `bin/kamal deploy` for later
updates. Advanced settings live in `docs/kamal-deployment.md`.

The supported fork boundary is configuration-only: operators may retain
release-pinned deployment settings in a fork, while modified application code
or images remain outside first-release support.

## Self-Hosted Product Boundary

- The full core product is unlimited and has no Stripe, plan-limit, or license-key dependency. Core includes projects, screenshot and multi-viewport review, annotations and replies, APIs, the CLI, and CLI-backed agent workflows; selling and operating the managed `screenote.ai` service remains SaaS-only. The legacy MCP runtime remains in source but is not a supported public integration surface.
- The supported first release is one container backed by SQLite and one persistent volume.
- Primary, cache, queue, and cable state use four SQLite files on that volume with WAL, full durability, bounded contention, and primary-state reconciliation for work lost from the separate queue database.
- Local filesystem storage is the default; operator-configured S3-compatible storage is optional.
- The instance is closed and invitation-only. Before claim, a one-time bootstrap token is the only account-creation path and atomically creates its persisted instance administrator. After claim, each project owner may admit collaborators to that project without separate instance-administrator approval.
- Authorization remains project-scoped: an invitation grants access only to its named project, and even the instance administrator does not receive implicit access to every project. The first release introduces no global Team entity. New local users establish durable credentials during invitation acceptance, so SMTP is not required for later sign-in.
- The instance administrator is a singleton recovery role, not a superuser over project content. It can inspect account identity/status, suspend or restore access, revoke sessions, issue single-use expiring local recovery links, and atomically transfer itself to another active account. A local operator can run `bin/rails screenote:instance:recover_administrator` to emit only a 15-minute private recovery URL on stdout, or `bin/rails 'screenote:instance:transfer_administrator[email@example.test]'` to transfer to an existing active account. Both commands use the same locked/audited services as the UI; neither reopens bootstrap, creates an account, sends mail, or joins a project. Runtime configuration and secrets stay outside the product UI under operator control. See [[instance-administration]].
- External transactional email through generic SMTP, social OAuth, S3, and monitoring are optional. Screenote runs no mail service; administrators can copy invitation links when email is unavailable.
- Screenshot originals and variants are never served through default reusable Active Storage routes. Application-owned proxy routes authenticate an active project principal and recheck membership for every byte request.
- Runtime application, bootstrap, and provider secrets live in ignored Kamal secret configuration and are passed only to the selected container environment. The bootstrap secret is removed from both the Kamal config and secret file after claim; secrets must not appear in image layers, process arguments, logs, diagnostics, or tracked configuration. `_FILE` loading remains available for the legacy qualification harness.
- OAuth and one-time link credentials become digest-only. Project-scoped OAuth is bound only after a user chooses a joined project on a server-owned consent/device screen. The SaaS credential conversion uses a stopped-process maintenance cutover because predecessor containers cannot read transformed rows.

## SaaS Boundary

The same revision must continue to run `screenote.ai` with PostgreSQL, Stripe, hosted object storage, email, OAuth, and monitoring. Self-hosted defaults must not weaken those production requirements.

## Deployment Configuration Boundary

Production now starts from one immutable `Screenote::Deployment` configuration. `SCREENOTE_EDITION` and `SCREENOTE_BASE_URL` are explicit, `SECRET_KEY_BASE` and the initial self-hosted bootstrap token require at least 32 bytes, and malformed origins or broad proxy trust fail before service. The canonical origin controls allowed hosts, URL generation, OmniAuth callbacks, redirects, secure cookies, and HTTP/HTTPS enforcement; IPv6 origins are normalized with exactly one bracket pair before ports are appended. A pre-Rails middleware removes forwarded client and origin headers unless the immediate peer belongs to `SCREENOTE_TRUSTED_PROXIES`, so a direct caller cannot forge a rate-limit identity or TLS termination.

SaaS production requires its four PostgreSQL roles plus Stripe, Resend, Google/GitHub OAuth, Honeybadger, hosted storage, and `SCREENOTE_SAAS_OPERATOR_EMAIL`. Self-hosted production defaults to local private storage and no mail, social OAuth, monitoring, or billing; each optional provider must be explicitly enabled with a complete configuration. No-mail mode does not draw password-reset routes or enqueue reset credentials. S3 storage applies `SCREENOTE_S3_PREFIX` to every object key and persists a credential-free namespace fingerprint covering service, endpoint, region, bucket, prefix, and path-style behavior.

The public `config/deploy.yml` is a self-hosted Kamal starter: one application
role, one `screenote_storage` named volume, Kamal Proxy with automatic HTTPS,
sanitized proxy-generated forwarding headers passed through the private
Thruster loopback hop, a cross-version asset bridge, local screenshot storage,
and mail/OAuth/monitoring disabled by default. A
fresh install temporarily includes `SCREENOTE_BOOTSTRAP_TOKEN`; after claim the
operator removes it and deploys again. External SMTP providers and generic S3
are enabled by uncommenting their environment keys and adding only their
secrets to `.kamal/secrets`; both SMTP username and password are secret because
providers such as Postmark use a token as the username. The starter explicitly
targets the first release's supported Linux AMD64 host. The hosted service has a separate complete
`config/deploy.saas.yml` and SaaS-only hooks, invoked through `bin/kamal-saas`,
so its PostgreSQL and provider requirements cannot leak into self-hosting.
`GET /up` remains process liveness, while `GET /ready` checks all four SQLite
schemas, volume writability, and selected Active Storage configuration without
calling external providers or disclosing a failing component. Kamal Proxy and
Thruster both bound request bodies at 30 MiB.

The repository's `bin/kamal` wrapper is release-aware while retaining the
standard `setup`, `deploy`, and `redeploy` commands. On a supported tag it
loads the immutable GitHub Release `public-evidence.json`, verifies the source,
manifest, OCI-label, qualification, and publication identities, and uses
Docker Buildx to mirror the unchanged parent manifest into Kamal's loopback
registry under the release source SHA. It then invokes Kamal with
`--skip-push`; the release image carries the `service=screenote` label Kamal
checks after its remote pull. A config-only deployment branch is accepted,
while other tracked divergence fails closed. A checkout with no supported
release tag reachable in its ancestry remains a warned development build, and
`SCREENOTE_KAMAL_SOURCE_BUILD=1` is the explicit unsupported custom-image
escape hatch. Cached public evidence lives in the
ignored `.kamal/releases/` directory. The hosted wrapper appends its config
option immediately after the parsed top-level command or subcommand group, and
the SaaS deploy guard does the same after `app`. This preserves isolation even
when a variadic command uses Thor's `--` delimiter; placing a class option
before the top-level command only prints help and does not perform the requested
operation.

The versioned minimum-host source contract is now
`config/release/minimum-host-v1.json`: Linux AMD64, 2 vCPUs, 4 GiB RAM, 40 GiB
free local SSD storage, and UID/GID 1000. The tracked
`script/self_hosted_load_driver` constrains the exact candidate container to
that CPU/RAM profile, creates 25 independently authenticated API sessions,
runs four overlapping exact 20 MiB uploads and a ten-minute 20-mutation/second
workload, includes scheduler backlog in core p95 latency, reconciles unique
mutation identities, drains upload processing, checks all four SQLite
databases, and emits only strict redacted evidence. The wrapper validates the
profile and the incompatible `screenote-load-smoke/v2` evidence shape. Capacity
is measured on the exact named volume mounted at `/rails/storage`, and bounded
process groups plus termination handling keep failed qualification commands
from occupying the runner indefinitely. Deterministic container and volume
names are marked for cleanup before Docker creation can complete, and the outer
shutdown grace covers both bounded cleanup operations. The qualification
workflow hashes the profile file bytes from the exact source commit and retains
the validated load measurements with the canonical qualification artifact.

The primary database stores exactly one constrained `Installation` identity: edition, ownership state, storage service, namespace fingerprint, and—until claim—the bootstrap digest. Before any mode-specific database preparation, the supported entrypoint runs a standalone, Bundler-backed deployment preflight that makes no provider connection. SaaS refuses a mounted self-hosted primary; self-hosted startup refuses retained SaaS database-role settings and inspects an existing local primary read-only for conflicting edition, storage service, storage namespace, or unclaimed bootstrap material. Schema preparation runs only after that complete persisted identity matches, and `Installations::Prepare` repeats the check after migrations as defense in depth. Credential rotation is allowed when the persisted namespace remains the same. See [[authentication]], [[data-model]], and [[dependencies]].

## Private Media and Processing Recovery

Default Active Storage blob, representation, disk, and direct-upload routes are disabled. Browser pages use `MediaController` URLs keyed by `ScreenshotImage` and an allowlisted original or named variant. Each request scopes the image through the current user's live project membership before downloading local or S3 bytes through the application, returns no provider redirect, and marks the response private and non-cacheable. Named variants must already have a tracked processed record; media GETs never invoke a decoder.

Both the legacy signed upload and manifest upload pass through `Snapshots::AttachImage`. It streams into a process-owned temporary file, enforces the 20 MiB declared and observed limit, verifies PNG/JPEG magic and declared/manifest identity, limits decoder concurrency, and rejects a dimension above 32,768 pixels or more than 50 million decoded pixels before attaching. The validated bytes are staged in the selected storage service before their Blob is attached, making Active Storage's later commit callback a no-op; a concurrent loser or failed database transaction removes its staged object, and the temporary file remains block-scoped.

An attached pending image is durable work intent. Dimension processing is handed to Solid Queue only after the attachment's outer database transaction commits, so a worker cannot discard a replacement job while the new blob reference is still invisible. `ScreenshotImages::EnsureProcessing` treats queue insertion failure as deferred work, and `ReconcileScreenshotProcessingJob` completes missing dimension and thumbnail work idempotently inline. The container runs reconciliation after database and installation preparation; Solid Queue repeats it every five minutes. See [[models/screenshot-image]] and [[services/annotation-crop-service]].

## Whole-Instance Operations

The public Kamal guide currently states the recovery boundary rather than
claiming a standalone backup package: operators must take a consistent,
quiesced, encrypted backup of the `screenote_storage` volume and, in S3 mode,
the selected bucket/prefix, then complete a restore drill. The older
`bin/self-host-backup` and `bin/self-host-restore` implementation still models
a Compose-based pre-release harness and is not linked from the public Kamal
path. Each legacy operations document now carries an explicit warning that it
is not a supported Kamal procedure. Migrating or replacing that implementation
is tracked in [[gaps]].

Only adjacent release upgrades are supported when release notes require them;
rollback means restoring the prior complete recovery point with its matching
application version. The exact Kamal-native backup/restore command contract
remains an open release task.

## Publication Safety

- GitGuardian full-history scanning gates the initial public source. After publication, protected-branch checks gate every default-branch update, and the same fail-closed policy gates tags and images.
- Publication requires no Open GitGuardian incident. Every confirmed credential must be revoked or rotated before resolution, regardless of perceived risk; ignored incidents are limited to documented false positives or non-secret test values proven incapable of authentication.
- Extending GitGuardian to other eligible public repositories is a separate initiative and does not authorize private-repository access.
- Release candidates build AMD64 and ARM64 OCI layouts once, import them into a trusted ephemeral scanner target, and pass both GitGuardian secret scanning and a pinned Critical/High vulnerability policy before any tag or registry mutation. Promotion is resumable only when every existing object exactly matches retained evidence.
- Public evidence contains only technical identities, versions, counts, dispositions, and hashes. Detailed scanner output remains private to trusted CI jobs.

### Prepared release controls and unresolved gates

The publication tree carries the Fizzy O'Saasy text adapted only to `Copyright © 2026, Future Spin Ltd.`, plus source-available contribution, security, support, third-party-notice, self-hosting, and release material. The validator checks the exact license bytes and notice directly; no separate legal or ownership attestation is part of publication.

The previously tracked but unused Rails encrypted credentials file is absent from the current tree. Ignore rules and Docker-context checks prevent accidental reintroduction. It does not create an inventory, rotation, history-rewrite, or publication-approval requirement.

GitGuardian duties are deliberately independent:

- the installed GitHub App must finish its historical scan and provide the exact required App check with skip actions disabled;
- the metadata-only required workflow checks out no code and requires a matching GitHub source whose monitoring state is exactly active, whose provider archive flag is exactly false, and whose top-level deletion flag is exactly false, then follows every strict same-origin incident page and rejects Open or unknown states; because GitHub runs `pull_request_target` against the base SHA, it replaces stale results with pending on the validated PR head and test-merge SHAs before querying, then posts success or generic error with narrow status-write permission; and
- checksum-pinned `ggshield` scans the frozen source history/current tree and the exact imported AMD64/ARM64 image manifests in trusted candidate CI using a fixed canonical instance and exact reviewed config path; Trivy and Syft likewise receive explicit trusted config paths, with an empty Trivy ignore file and suppressed-finding reporting, so repository or runner auto-configuration cannot weaken vulnerability scans or SBOM inventory.

The self-hosted browser collaboration matrix supplies its own explicit test-only bootstrap token for the unclaimed-installation scenario and removes that value for the claimed-installation scenarios. The gate therefore has the same admission behavior when run directly by an operator as it does under GitHub Actions, without depending on inherited CI configuration. Instance-administration controller coverage is named in the self-hosted positive manifest rather than relying on tests that skip when the SaaS route set is booted.

Contributors run `script/release_test_matrix self-hosted` for the edition-aware
self-hosted suite. Running the entire SaaS suite under a self-hosted boot is not
a valid gate because self-hosting intentionally removes billing, SaaS admin,
hosted OAuth, and mail-only routes; the positive manifest selects the shared
and self-hosted contracts explicitly.

The checked-in branch/tag rulesets are templates with zero-valued GitHub App IDs, not evidence of live protection. Main has no bypass, while release-tag creation permits only the dedicated release App and a second no-bypass ruleset makes created tags immutable. Their actual IDs, exports, protected `source-release` environment, GHCR permissions, immutable-release setting, and private vulnerability reporting must be configured and independently verified. The release App has repository Administration read solely so the no-checkout promotion job can re-read the immutable-release setting and require its exact enabled response before any registry, tag, attestation, or release mutation.

`.github/workflows/release.yml` separates a non-publishing retained candidate from promotion. Candidate mode binds the current protected default-branch commit to one multi-platform OCI layout, verified imported manifests/configs, secret/vulnerability results, SBOMs, and provenance input. Publish mode accepts only an exact successful candidate run/bundle hash and exactly one direct-parent release-metadata commit, then scans the final notes and technical evidence bytes. The no-checkout promotion job is gated by `source-release`, verifies the current run has exactly one approval for that environment, and publishes no approval or ownership record. It reruns the live GitGuardian source/incident gate, preflights image/tag/attestation/release together, accepts only a strict exact prefix, signs retained provenance, and re-verifies all four objects.

Pull-request jobs are source-contract checks only and cannot establish release
qualification. `.github/workflows/release-qualification.yml` must instead run
against the retained candidate bytes on configured native AMD64, native ARM64,
and versioned minimum-host capacity. Its one canonical artifact binds the exact
source, candidate run and bundle, platform manifests, immutable CLI tag/commit,
and eight results: self-hosted and SaaS boot on each architecture,
backup/restore, SQLite load, and public CLI behavior over HTTP and HTTPS.
Each SaaS result must come from the candidate's unmodified production
entrypoint and default server command against digest-pinned PostgreSQL 16,
with all four database roles and the SaaS installation identity verified.
Native image qualification also verifies the Kamal service label and the exact
source, revision, and version labels before booting the candidate.
The public CLI driver runs once per transport and each structured result binds
its own canonical origin, candidate digest, CLI tag/commit, and TLS posture;
HTTPS also proves wrong-CA and wrong-hostname rejection.
Promotion live-verifies the qualification workflow identity, attempt, exact job
set, artifact ID/archive digest, downloaded record bytes, candidate bindings,
and current CLI tag; missing or ambiguous API state fails closed. Native runner
labels, the tracked public-CLI driver, candidate-backed origins, the immutable
CLI tag, and an exact successful run on the tracked minimum-host profile are not
configured or retained yet, so qualification cannot currently emit publishable
evidence.

`bin/release-validate` has independent `prepare`, technical `evidence`, and `publish` modes. `docs/releases/PUBLICATION_BLOCKED.md` is a hard sentinel: while present, even otherwise valid evidence cannot publish. Fixture evidence is also rejected in publish mode. Live GitGuardian, repository-setting, CLI-tag, native-runner, driver/origin, and exact-candidate evidence is still incomplete, so no source tag, image, attestation, or release is ready.

## Scope

The initial predecessor-free release remains blocked until the exact
Kamal-native backup, restore, and runtime qualification contract is complete.
The first successor release must also qualify its adjacent upgrade and rollback
path. Ordinary `bin/kamal deploy` assumes backward-compatible migrations; a
release that needs a stopped-process migration must publish explicit
maintenance and rollback instructions. The older Compose commands remain an
internal qualification harness and are not a supported operator contract.
Self-hosted PostgreSQL, high availability, clustering, enterprise SSO, SaaS
import/export, storage migration tooling, and in-product updates remain
deferred. See [[plans-and-initiatives]] and the historical implementation plan
at `docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md`.

See also: [[architecture]], [[dependencies]], [[decisions]], [[testing-and-ci]]
