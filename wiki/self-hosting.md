---
title: Self-Hosted Distribution
type: initiative
source: docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md
created: 2026-08-05
updated: 2026-08-06
tags: [self-hosting, docker, licensing, storage, release]
---

# Self-Hosted Distribution

**TLDR:** Screenote has an implementation-ready plan for a source-available, single-container self-hosted edition alongside `screenote.ai`. Publication remains blocked on legal, secret-history, and repository-protection evidence.

## Distribution Model

- Future Spin Ltd will publish Screenote under the O'Saasy license.
- One public repository will carry the shared core and an explicitly enabled SaaS capability.
- Tagged releases will provide a prebuilt container image after quality, security, migration, and self-hosted smoke gates pass.
- The production image starts from a digest-pinned Ruby 3.4.10 Alpine 3.24 multi-architecture index. Transitional Go CLI sources are not copied into the Rails runtime image, so its SBOM and vulnerability gate describe shipped runtime software rather than separately tested source.
- Public language should use “source-available and self-hostable” because O'Saasy restricts directly competing hosted services.

## Self-Hosted Product Boundary

- The full core product is unlimited and has no Stripe, plan-limit, or license-key dependency. Core includes projects, screenshot and multi-viewport review, annotations and replies, APIs, CLI, MCP, and agent workflows; selling and operating the managed `screenote.ai` service remains SaaS-only.
- The supported first release is one container backed by SQLite and one persistent volume.
- Primary, cache, queue, and cable state use four SQLite files on that volume with WAL, full durability, bounded contention, and primary-state reconciliation for work lost from the separate queue database.
- Local filesystem storage is the default; operator-configured S3-compatible storage is optional.
- The instance is closed and invitation-only. Before claim, a one-time bootstrap token is the only account-creation path and atomically creates its persisted instance administrator. After claim, each project owner may admit collaborators to that project without separate instance-administrator approval.
- Authorization remains project-scoped: an invitation grants access only to its named project, and even the instance administrator does not receive implicit access to every project. The first release introduces no global Team entity. New local users establish durable credentials during invitation acceptance, so SMTP is not required for later sign-in.
- The instance administrator is a singleton recovery role, not a superuser over project content. It can inspect account identity/status, suspend or restore access, revoke sessions, issue single-use expiring local recovery links, and atomically transfer itself to another active account. A local operator can run `bin/rails screenote:instance:recover_administrator` to emit only a 15-minute private recovery URL on stdout, or `bin/rails 'screenote:instance:transfer_administrator[email@example.test]'` to transfer to an existing active account. Both commands use the same locked/audited services as the UI; neither reopens bootstrap, creates an account, sends mail, or joins a project. Runtime configuration and secrets stay outside the product UI under operator control. See [[instance-administration]].
- SMTP, social OAuth, S3, and monitoring are optional. Administrators can copy invitation links when mail is unavailable.
- Screenshot originals and variants are never served through default reusable Active Storage routes. Application-owned proxy routes authenticate an active project principal and recheck membership for every byte request.
- Runtime application, bootstrap, and provider secrets are generated at the documented strength and mounted from restricted Compose secret files. The bootstrap secret can be removed after claim; secrets must not appear in image layers, process arguments, logs, diagnostics, or tracked configuration.
- OAuth and one-time link credentials become digest-only. Project-scoped OAuth is bound only after a user chooses a joined project on a server-owned consent/device screen. The SaaS credential conversion uses a stopped-process maintenance cutover because predecessor containers cannot read transformed rows.

## SaaS Boundary

The same revision must continue to run `screenote.ai` with PostgreSQL, Stripe, hosted object storage, email, OAuth, and monitoring. Self-hosted defaults must not weaken those production requirements.

## Deployment Configuration Boundary

Production now starts from one immutable `Screenote::Deployment` configuration. `SCREENOTE_EDITION` and `SCREENOTE_BASE_URL` are explicit, `SECRET_KEY_BASE` and the initial self-hosted bootstrap token require at least 32 bytes, and malformed origins or broad proxy trust fail before service. The canonical origin controls allowed hosts, URL generation, OmniAuth callbacks, redirects, secure cookies, and HTTP/HTTPS enforcement; IPv6 origins are normalized with exactly one bracket pair before ports are appended. A pre-Rails middleware removes forwarded client and origin headers unless the immediate peer belongs to `SCREENOTE_TRUSTED_PROXIES`, so a direct caller cannot forge a rate-limit identity or TLS termination.

SaaS production requires its four PostgreSQL roles plus Stripe, Resend, Google/GitHub OAuth, Honeybadger, hosted storage, and `SCREENOTE_SAAS_OPERATOR_EMAIL`. Self-hosted production defaults to local private storage and no mail, social OAuth, monitoring, or billing; each optional provider must be explicitly enabled with a complete configuration. No-mail mode does not draw password-reset routes or enqueue reset credentials. S3 storage applies `SCREENOTE_S3_PREFIX` to every object key and persists a credential-free namespace fingerprint covering service, endpoint, region, bucket, prefix, and path-style behavior.

The supported Compose base is the claimed local-storage mode: one application
service, one persistent volume, and no bootstrap declaration. A fresh instance
adds `compose.bootstrap.yaml` only until claim, then restarts without that
overlay or token. Generic S3, SMTP, Google OAuth, GitHub OAuth, and Honeybadger
are independent additive overlays; every provider credential is mounted from a
UID-1000-owned, non-group-readable file rather than stored in Compose
environment values. `GET /up` remains process liveness, while the generic
`GET /ready` response checks all four SQLite schemas, volume writability, and
the selected Active Storage configuration without calling external providers
or disclosing a failing component. The release image also bounds Thruster
request bodies at 30 MiB, preserving the 28 MiB MCP base64 JSON contract with
finite envelope overhead.

The primary database stores exactly one constrained `Installation` identity: edition, ownership state, storage service, namespace fingerprint, and—until claim—the bootstrap digest. Before any mode-specific database preparation, the supported entrypoint runs a standalone, Bundler-backed deployment preflight that makes no provider connection. SaaS refuses a mounted self-hosted primary; self-hosted startup refuses retained SaaS database-role settings and inspects an existing local primary read-only for conflicting edition, storage service, storage namespace, or unclaimed bootstrap material. Schema preparation runs only after that complete persisted identity matches, and `Installations::Prepare` repeats the check after migrations as defense in depth. Credential rotation is allowed when the persisted namespace remains the same. See [[authentication]], [[data-model]], and [[dependencies]].

## Private Media and Processing Recovery

Default Active Storage blob, representation, disk, and direct-upload routes are disabled. Browser pages use `MediaController` URLs keyed by `ScreenshotImage` and an allowlisted original or named variant. Each request scopes the image through the current user's live project membership before downloading local or S3 bytes through the application, returns no provider redirect, and marks the response private and non-cacheable. Named variants must already have a tracked processed record; media GETs never invoke a decoder.

Both the legacy signed upload and manifest upload pass through `Snapshots::AttachImage`. It streams into a process-owned temporary file, enforces the 20 MiB declared and observed limit, verifies PNG/JPEG magic and declared/manifest identity, limits decoder concurrency, and rejects a dimension above 32,768 pixels or more than 50 million decoded pixels before attaching. The validated bytes are staged in the selected storage service before their Blob is attached, making Active Storage's later commit callback a no-op; a concurrent loser or failed database transaction removes its staged object, and the temporary file remains block-scoped.

An attached pending image is durable work intent. Dimension processing is handed to Solid Queue only after the attachment's outer database transaction commits, so a worker cannot discard a replacement job while the new blob reference is still invisible. `ScreenshotImages::EnsureProcessing` treats queue insertion failure as deferred work, and `ReconcileScreenshotProcessingJob` completes missing dimension and thumbnail work idempotently inline. The container runs reconciliation after database and installation preparation; Solid Queue repeats it every five minutes. See [[models/screenshot-image]] and [[services/annotation-crop-service]].

## Whole-Instance Operations

`bin/self-host-backup` and `bin/self-host-restore` are the supported host-side operations. They require host uid/gid 1000, immutable image digests, restricted operator files, Docker Compose, an operator-held age identity for confidentiality, and a separate random single-link authentication-key file for origin authenticity. The key is never archived and cannot alias configuration, Compose, secrets, recovery identity, running application storage, or backup inputs. Backup verifies the healthy running image and proves that the running container's exact read-only secrets and writable local Docker volume match the sanitized rendered Compose model before quiescing. It treats the service as stopped immediately after a successful Compose stop, even when the following inspection fails, so the failure warning never incorrectly suggests that service continued running. It then validates all four SQLite databases and the canonical blob inventory and writes an age-encrypted set whose completion-marker HMAC authenticates the encrypted manifest; a failed backup leaves the service stopped. Restore authenticates that marker before Docker mutation, then repeats authentication after private input staging, passes the age identity through an inherited descriptor rather than persistent staging, validates and extracts into an explicitly named empty volume, verifies every database and blob, reconciles durable processing work, and only then starts the restored service. The target mount uses Docker's `volume-nocopy` behavior so an image-owned `/rails/storage/.keep` cannot make a fresh volume look populated or alter it before validation.

S3 backups require an operator snapshot hook whose evidence binds the quiescence window, namespace, canonical object-set digest, provider snapshot reference, and authenticated age encryption to the same recipient. Screenote validates that contract but does not treat provider assertions as independently proven. Restore publication is all-or-nothing where possible and writes a failure marker if rollback itself cannot complete. Only adjacent release upgrades are supported; rollback means restoring the prior complete set with its exact predecessor image. Rootless Docker, user-namespace remapping, and non-1000 host identities are outside the initial support contract. See `docs/self-hosting/backup-and-restore.md`, `docs/self-hosting/upgrades.md`, and `docs/self-hosting/diagnostics.md`.

## Publication Safety

- GitGuardian full-history scanning gates the initial public source. After publication, protected-branch checks gate every default-branch update, and the same fail-closed policy gates tags and images.
- Publication requires no Open GitGuardian incident. Every confirmed credential must be revoked or rotated before resolution, regardless of perceived risk; ignored incidents are limited to documented false positives or non-secret test values proven incapable of authentication.
- Revoked credentials may remain in reviewed history only with documented security and legal approval. Non-revocable secrets, protected personal or confidential data, third-party intellectual property, or unapproved retention require rewritten or replacement history.
- Extending GitGuardian to other eligible public repositories is a separate initiative and does not authorize private-repository access.
- Release candidates build AMD64 and ARM64 OCI layouts once, import them into a trusted ephemeral scanner target, and pass both GitGuardian secret scanning and a pinned Critical/High vulnerability policy before any tag or registry mutation. Promotion is resumable only when every existing object exactly matches retained evidence.
- Public evidence contains hashes, opaque identifiers, versions, and dispositions only. Credential inventories, incident detail, vulnerability findings, and waivers remain in a restricted evidence store.

### Prepared release controls and unresolved gates

The publication tree now carries the Fizzy O'Saasy text adapted only to `Copyright © 2026, Future Spin Ltd.`, plus source-available contribution, security, support, third-party-notice, self-hosting, and release material. This is intended licensing, not legal clearance: chain of title, the exact notice/text, dependency and base-image licenses, and candidate history still require documented legal approval.

The previously tracked Rails encrypted credentials are absent from the current tree, ignored against accidental reintroduction, and excluded from the container context. A redacted audit proves the ciphertext remains reachable in existing history. It was not decrypted because authorization and the key were unavailable. Publication therefore remains blocked until authorized inventory, provider revocation/rotation, and security/legal history-retention or rewrite disposition are recorded.

GitGuardian duties are deliberately independent:

- the installed GitHub App must finish its historical scan and provide the exact required App check with skip actions disabled;
- the metadata-only required workflow checks out no code and requires a matching GitHub source whose monitoring state is exactly active, then follows every strict same-origin incident page and rejects Open or unknown states; because GitHub runs `pull_request_target` against the base SHA, it replaces stale results with pending on the validated PR head and test-merge SHAs before querying, then posts success or generic error with narrow status-write permission; and
- checksum-pinned `ggshield` scans the frozen source history/current tree and the exact imported AMD64/ARM64 image manifests in trusted candidate CI using a fixed canonical instance and exact reviewed config path; Trivy and Syft likewise receive explicit trusted config paths, with an empty Trivy ignore file and suppressed-finding reporting, so repository or runner auto-configuration cannot weaken vulnerability scans or SBOM inventory.

The self-hosted browser collaboration matrix supplies its own explicit test-only bootstrap token for the unclaimed-installation scenario and removes that value for the claimed-installation scenarios. The gate therefore has the same admission behavior when run directly by an operator as it does under GitHub Actions, without depending on inherited CI configuration. Instance-administration controller coverage is named in the self-hosted positive manifest rather than relying on tests that skip when the SaaS route set is booted.

The checked-in branch/tag rulesets are templates with zero-valued GitHub App IDs, not evidence of live protection. Main has no bypass, while release-tag creation permits only the dedicated release App and a second no-bypass ruleset makes created tags immutable. Their actual IDs, exports, protected `source-release` environment, GHCR permissions, immutable-release setting, and private vulnerability reporting must be configured and independently verified. The release App has repository Administration read solely so the no-checkout promotion job can re-read the immutable-release setting and require its exact enabled response before any registry, tag, attestation, or release mutation.

`.github/workflows/release.yml` separates a non-publishing retained candidate from promotion. Candidate mode binds the current protected default-branch commit to one multi-platform OCI layout, verified imported manifests/configs, secret/vulnerability results, SBOMs, and provenance input. Publish mode accepts only an exact successful candidate run/bundle hash and exactly one direct-parent evidence-only authorizing commit, then scans the exact final notes/evidence bytes. The committed `preauthorization` records a release-maintainer decision and intended environment, but it is explicitly not proof of GitHub's protected-environment review. The no-checkout promotion job's first post-environment step reads the current run's review history and requires exactly one approved review covering exactly `source-release`; it publishes only a redacted `environment-approval.json` containing repository, source/authorizing commit, run/attempt, state, and a canonical review digest—never reviewer identity or comment. An exact release retry downloads those immutable bytes, binds the historical attempt to the ref-qualified workflow path and default branch, and revalidates the historical review before continuing. Only then does promotion rerun the live GitGuardian source/incident gate, preflight image/tag/attestation/release together, accept a strict exact prefix, sign retained provenance with separate authorizing-workflow identity, and finally reverify all four objects.

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
The public CLI driver runs once per transport and each structured result binds
its own canonical origin, candidate digest, CLI tag/commit, and TLS posture;
HTTPS also proves wrong-CA and wrong-hostname rejection.
Promotion live-verifies the qualification workflow identity, attempt, exact job
set, artifact ID/archive digest, downloaded record bytes, candidate bindings,
and current CLI tag; missing or ambiguous API state fails closed. Native runner
labels, the minimum-host profile, tracked load/CLI drivers, candidate-backed
origins, and the immutable CLI tag are not configured yet, so qualification
cannot currently emit publishable evidence.

`bin/release-validate` has independent `prepare`, redacted `evidence`, and `publish` modes. `docs/releases/PUBLICATION_BLOCKED.md` is a hard sentinel: while present, even otherwise valid evidence cannot publish. Fixture evidence is also rejected in publish mode. The current external GitGuardian, credential, legal, repository-setting, CLI-tag, and exact-candidate evidence does not exist, so no visibility change, source tag, image, attestation, or release is authorized.

## Scope

The first release supports sequential upgrades between named adjacent releases and retains immutable images for each supported hop. Supported backup/restore commands quiesce the service, bind the full volume and local/S3 blob inventory to an origin-authenticated encrypted manifest, encrypt to an operator-held age identity, and authenticate with a separate operator-held random key; both recovery factors stay outside the host and backup. Before quiescing and again after restore, the operator command renders Compose under a sanitized environment and requires the portable `secrets/` tree to equal the complete file-backed secret set consumed by the service; before backup it also binds the rendered named storage volume to the running container's local-driver mount. Rollback restores the exact pre-upgrade set with the recorded predecessor image and may discard later writes; an older image must never open migrated state. It defers self-hosted PostgreSQL, high availability, clustering, enterprise SSO, SaaS import/export, storage migration tooling, and in-product updates. See [[plans-and-initiatives]] and the implementation-ready plan at `docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md`.

See also: [[architecture]], [[dependencies]], [[decisions]], [[testing-and-ci]]
