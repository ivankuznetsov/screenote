---
title: Self-Hosted Distribution
type: initiative
source: Dockerfile, bin/docker-entrypoint, app/jobs/reconcile_screenshot_processing_job.rb, lib/screenote/deployment.rb, docs/once-deployment.md, docs/releases/PUBLICATION_BLOCKED.md, config/deploy.saas.yml
created: 2026-08-05
updated: 2026-08-10
tags: [self-hosting, once, docker, deployment, storage, release, kamal-saas]
---

# Self-Hosted Distribution

**TLDR:** Screenote implements a source-available, single-server self-hosted edition alongside `screenote.ai`. Public self-hosting uses ONCE with the GHCR `latest` release channel, one application container, four SQLite databases, and one durable volume; it requires neither a fork nor a source checkout. Kamal remains an internal deployment tool for hosted `screenote.ai`. Publication is still blocked until the retained ONCE runtime and recovery drill passes.

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

Public installation docs lead directly with ONCE and the latest release image;
they do not expose the repository's internal publication sentinel or label the
operator path as a development preview. Operators install released stock ONCE
with `curl https://get.once.com | ONCE_INTERACTIVE=false sh`, then deploy
`ghcr.io/ivankuznetsov/screenote:latest` with an explicit `--host` and matching
`SCREENOTE_BASE_URL`. When that installer adds a non-root operator to the
Docker group, the operator reconnects once before deployment so the current
shell can reach Docker. Automatic updates remain enabled. Release evidence still
names the exact ONCE version and image digest used for qualification, and bare
`once update HOST` requests an immediate update.

Screenote takes its canonical origin from the explicit base URL. The first
visitor atomically claims the administrator, so there is no setup credential
to generate, enter, retain, or remove. No upstream Screenote-specific ONCE
integration, repository fork, source checkout, public Kamal configuration, or
local image build is part of the supported path. HTTP-only and initial S3
examples in `docs/once-deployment.md` provide matching explicit base URLs.

## Self-Hosted Product Boundary

- The full core product is unlimited and has no Stripe, plan-limit, or license-key dependency. Core includes projects, screenshot and multi-viewport review, annotations and replies, APIs, the CLI, and CLI-backed agent workflows; selling and operating the managed `screenote.ai` service remains SaaS-only. The legacy MCP runtime remains in source but is not a supported public integration surface.
- The supported first release is one container backed by SQLite and one persistent ONCE volume mounted at both `/storage` and `/rails/storage`.
- Primary, cache, queue, and cable state use four SQLite files on that volume with WAL, full durability, bounded contention, and primary-state reconciliation for work lost from the separate queue database.
- Local filesystem storage is the default; operator-configured S3-compatible storage is optional.
- The instance is closed and invitation-only after setup. While the persisted Installation is unclaimed, the first completed setup atomically creates and records its administrator under a database lock; concurrent claim attempts have exactly one winner. After claim, each project owner may admit collaborators to that project without separate instance-administrator approval.
- Authorization remains project-scoped: an invitation grants access only to its named project, and even the instance administrator does not receive implicit access to every project. The first release introduces no global Team entity. New local users establish durable credentials during invitation acceptance, so SMTP is not required for later sign-in.
- The instance administrator is a singleton recovery role, not a superuser over project content. It can inspect account identity/status, suspend or restore access, revoke sessions, issue single-use expiring local recovery links, and atomically transfer itself to another active account. A local operator can run `bin/rails screenote:instance:recover_administrator` to emit only a 15-minute private recovery URL on stdout, or `bin/rails 'screenote:instance:transfer_administrator[email@example.test]'` to transfer to an existing active account. Both commands use the same locked/audited services as the UI; neither reopens bootstrap, creates an account, sends mail, or joins a project. Runtime configuration and secrets stay outside the product UI under operator control. See [[instance-administration]].
- External transactional email through generic SMTP, social OAuth, S3, and monitoring are optional. Screenote runs no mail service; administrators can copy invitation links when email is unavailable.
- Screenshot originals and variants are never served through default reusable Active Storage routes. Application-owned proxy routes authenticate an active project principal and recheck membership for every byte request.
- ONCE generates and retains the application secret, while optional provider values live in the application's ONCE environment. No administrator-claim credential exists. Provider secrets must not appear in image layers, logs, diagnostics, or tracked configuration. `_FILE` loading remains available for the legacy qualification harness.
- OAuth and one-time link credentials become digest-only. Project-scoped OAuth is bound only after a user chooses a joined project on a server-owned consent/device screen. The SaaS credential conversion uses a stopped-process maintenance cutover because predecessor containers cannot read transformed rows. The operator proves quiescence and a fresh recoverable backup before migration. The cutover then lets each migration use its adapter-supported transaction behavior and verifies migration versions, stored digests, and runtime lookups; it does not promise one outer transaction across the chain. An interrupted run remains in maintenance until the version-aware, idempotent checks resume successfully or the verified backup is restored.

## SaaS Boundary

The same revision must continue to run `screenote.ai` with Stripe, hosted object storage, email, OAuth, and monitoring. Shared models, services, tests, CI, and release qualification use Active Record rather than requiring a database adapter. The current hosted Kamal profile may still provision PostgreSQL, while self-hosting retains its supported four-file SQLite topology; neither runtime choice may leak edition-only providers or defaults into the other.

## Deployment Configuration Boundary

Production starts from one immutable `Screenote::Deployment` configuration.
The release image defaults `SCREENOTE_EDITION=self_hosted`, enables Thruster
forwarding, and trusts only the Thruster loopback peer. The ONCE path declares
two forwarding hops: ONCE's Kamal Proxy and Thruster. At boot it resolves the
configured proxy hostname with a bounded lookup, then refreshes that identity
through a short synchronized cache. A failed refresh discards the stale
identity. Before Rails derives request identity, the boundary promotes the
preceding address only when the final forwarded hop matches the current
resolved proxy identity; a sibling that bypasses the proxy, or traffic handled
during a failed refresh, is attributed to its own final address. It then
replaces `REMOTE_ADDR`, removes every forwarded header, and applies the
canonical scheme from the explicit base URL. A
caller-supplied prefix therefore cannot control session audit IPs, rate-limit
buckets, redirects, or TLS identity, and Docker's chosen private subnet is
irrelevant. The standard ONCE namespace uses `once-proxy`; custom qualification
namespaces explicitly supply their `<namespace>-proxy` name. This is pinned to
and exercised against the supported ONCE version because ONCE v0.3.0 exposes
the name through Docker container-name DNS. ONCE supplies `SECRET_KEY_BASE`;
operators supply the canonical origin as `SCREENOTE_BASE_URL` in `once deploy`
and match its scheme and hostname to the ONCE flags. Malformed origins or broad
proxy trust fail before service. The canonical origin
controls allowed hosts, URL generation, OmniAuth callbacks, redirects, secure
cookies, and HTTP/HTTPS enforcement. Failure to resolve a required two-hop
proxy identity stops boot. Direct-container qualification declares one
Thruster hop; additional upstream proxies are not part of the first release's
supported topology.

The current hosted Kamal configuration supplies PostgreSQL URLs for its four database roles plus Stripe, Resend, Google/GitHub OAuth, Honeybadger, hosted storage, and `SCREENOTE_SAAS_OPERATOR_EMAIL`. That is a deployment selection, not an application-level adapter requirement. Self-hosted production defaults to local private storage and no mail, social OAuth, monitoring, or billing; each optional provider must be explicitly enabled with a complete configuration. No-mail mode does not draw password-reset routes or enqueue reset credentials. S3 storage applies `SCREENOTE_S3_PREFIX` to every object key and persists a credential-free namespace fingerprint covering service, endpoint, region, bucket, prefix, and path-style behavior.

ONCE's stable channel is the public deployment layer. It runs the published image on port
80, routes through its Kamal Proxy, checks `GET /up`, creates the durable
application volume, and mounts that one volume at both `/storage` and
`/rails/storage`. The dual mount satisfies ONCE's application contract without
duplicating data: all four SQLite files and local Active Storage objects still
share one recovery unit. ONCE pauses the container when taking a volume backup,
because Screenote does not publish a pre-backup hook.

The public stock-ONCE deployment follows
`ghcr.io/ivankuznetsov/screenote:latest` with automatic updates enabled and an
explicit `SCREENOTE_BASE_URL`. A bare `once update HOST` remains the
immediate-update operation. Generic SMTP
interoperates with ONCE's Email settings: Screenote accepts
`MAILER_FROM_ADDRESS` and enables
SMTP when ONCE supplies `SMTP_ADDRESS`, unless an explicit
`SCREENOTE_SMTP_ENABLED=false` disables it. Generic S3 remains a custom
environment configuration selected during the advanced first deployment,
before Screenote boots and persists its storage identity.

The hosted service has a separate complete `config/deploy.saas.yml` and
SaaS-only hooks, invoked through `bin/kamal-saas`. The repository's `bin/kamal`
is the ordinary gem binstub and is not a public self-hosting wrapper. This keeps
hosted database and provider requirements out of ONCE self-hosting. `GET /up`
remains process liveness, while `GET /ready` checks all four SQLite schemas,
volume writability, and selected Active Storage configuration without calling
external providers or disclosing a failing component. ONCE's Kamal Proxy and
Thruster both bound request bodies at 30 MiB.

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

The primary database stores exactly one constrained `Installation` identity:
edition, ownership state, storage service, namespace fingerprint, and the
administrator relationship after claim. Before any mode-specific database
preparation, the supported entrypoint runs a standalone, Bundler-backed
deployment preflight that makes no provider connection. SaaS refuses a mounted
self-hosted primary; self-hosted startup refuses retained SaaS database-role
settings and inspects an existing local primary read-only for conflicting
edition, storage service, storage namespace, or ownership state. Schema
preparation runs only after that persisted identity matches, and
`Installations::Prepare` repeats the check after migrations as defense in
depth. Provider credential rotation is allowed when the persisted storage
namespace remains the same. See [[models/authentication-token]], [[data-model]],
and [[dependencies]].

## Private Media and Processing Recovery

Default Active Storage blob, representation, disk, and direct-upload routes are disabled. Browser pages use `MediaController` URLs keyed by `ScreenshotImage` and an allowlisted original or named variant. Each request scopes the image through the current user's live project membership before downloading local or S3 bytes through the application, returns no provider redirect, and marks the response private and non-cacheable. Named variants must already have a tracked processed record; media GETs never invoke a decoder.

Both the legacy signed upload and manifest upload pass through `Snapshots::AttachImage`. It streams into a process-owned temporary file, enforces the 20 MiB declared and observed limit, verifies PNG/JPEG magic and declared/manifest identity, limits decoder concurrency, and rejects a dimension above 32,768 pixels or more than 50 million decoded pixels before attaching. The validated bytes are staged in the selected storage service before their Blob is attached, making Active Storage's later commit callback a no-op; a concurrent loser or failed database transaction removes its staged object, and the temporary file remains block-scoped.

An attached pending image is durable work intent. Dimension processing is handed to Solid Queue only after the attachment's outer database transaction commits, so a worker cannot discard a replacement job while the new blob reference is still invisible. `ScreenshotImages::EnsureProcessing` treats queue insertion failure as deferred work, and `ReconcileScreenshotProcessingJob` completes missing dimension and thumbnail work idempotently inline. After database, installation, and authentication-key preparation, the entrypoint enqueues one reconciliation job and fails startup if Solid Queue cannot accept it. Puma and its Solid Queue plugin can therefore begin serving without synchronously walking the full image corpus; the recurring schedule repeats reconciliation every five minutes. See [[models/screenshot-image]] and [[services/annotation-crop-service]].

## Whole-Instance Operations

ONCE backs up local state by pausing Screenote and copying the durable volume,
which contains all four SQLite roles and, in local-storage mode, every
screenshot object. ONCE also retains application settings, so backup archives
must be encrypted, access-restricted, and copied off the application host. In
S3 mode the ONCE archive still protects the databases, but recovery of the
external bucket and exact prefix remains the operator's and storage provider's
responsibility. Database and object-store recovery points must match.

The simple public install stores the moving `latest` reference in ONCE's
settings, and therefore in its backup. Restoring that archive pulls the current
release rather than pinning the historical application version. A deployment
that requires version-pinned rollback must use the immutable reference from the
GitHub Release instead of the moving channel.

The older `bin/self-host-backup` and `bin/self-host-restore` implementation
remains an internal Compose-based qualification harness and is not the public
ONCE operator path. Public operations use ONCE's backup and restore commands;
the first supported release still requires retained evidence that those
commands recover Screenote correctly.

ONCE enables application auto-update for the stock deployment. Release notes must
identify any update that needs special maintenance rather than ordinary
automatic replacement; operators can also request the current release
immediately with `once update HOST`.

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

The self-hosted browser collaboration matrix exercises an unclaimed instance
without any setup secret, including concurrent first-visitor submissions, then
exercises the invitation-only claimed state. The gate therefore has the same
admission behavior when run directly by an operator as it does under GitHub
Actions, without depending on inherited CI configuration.
Instance-administration controller coverage is named in the self-hosted
positive manifest rather than relying on tests that skip when the SaaS route
set is booted.

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
Each SaaS result still comes from the exact candidate's unmodified production
entrypoint and default server command. Qualification supplies four
role-specific database URLs, verifies their primary, cache, queue, and cable
connections through Active Record, and verifies the SaaS installation
identity without asserting a database adapter or server version. This
URL-driven contract preserves both exact-image SaaS boot targets while leaving
the hosted Kamal profile free to select PostgreSQL.
Native image qualification also verifies the image service label and the exact
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

The initial predecessor-free release remains blocked until a retained Linux
drill installs the supported released stock ONCE version named in the evidence,
deploys the exact candidate with an explicit matching base URL, verifies
proxy identity and forwarding, restarts with persistent state, exercises the
moving release channel, and completes ONCE backup and restore for all four SQLite roles
and local files. S3 qualification must separately recover the matching
external namespace. Every successor release must qualify direct update and
restore from every earlier published release, plus its immediate
predecessor rollback path. An ordinary ONCE image update assumes
backward-compatible migrations; a
release that needs a stopped-process migration must publish explicit
maintenance, verified backup/restore, resumable verification, and rollback
instructions; it must not claim that one outer transaction covers the whole
migration chain. The older Compose commands remain an
internal qualification harness and are not a supported operator contract.
Self-hosted PostgreSQL, high availability, clustering, enterprise SSO, SaaS
import/export, storage migration tooling, and in-product updates remain
deferred. See [[plans-and-initiatives]] and the historical implementation plan
at `docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md`.

See also: [[architecture]], [[dependencies]], [[decisions]], [[testing-and-ci]]
