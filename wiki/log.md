# Wiki Changelog

Append-only log of all wiki operations.

<!-- BEGIN GENERATED WIKI LOG FRAGMENTS -->
## [2026-08-06] Keep focused Rails CI jobs runtime-complete

**Action:** Added libvips installation to the focused backup/restore CI job and
a workflow contract that requires the package before Rails setup. Documented
that the Vips initializer makes the native runtime a boot dependency even for
focused tests that do not directly transform images.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260806T114500Z-focused-ci-runtime-dependency.md, wiki/log.md

**Source:** .github/workflows/ci.yml, the backup/restore CI failure, and the
release artifact workflow contract

## [2026-08-06] Separate source contracts from exact release qualification

**Action:** Added a dedicated fail-closed release-qualification workflow and
made promotion live-verify its exact run, job set, retained artifact bytes,
candidate identities, and immutable CLI tag. Pull-request results are now
explicitly source-contract evidence only. SaaS qualification boots the exact
candidate through its production entrypoint against pinned PostgreSQL 16, and
the public CLI driver must return independently validated HTTP and HTTPS
evidence with strict origin, candidate, CLI, and TLS bindings. Documented the
native runner, minimum-host, tracked driver, candidate-origin, and CLI-tag
prerequisites that still block publication.

**Pages updated:** wiki/self-hosting.md, wiki/testing-and-ci.md, wiki/gaps.md,
wiki/log.d/20260806T113000Z-exact-release-qualification.md, wiki/log.md

**Source:** .github/workflows/release-qualification.yml,
.github/workflows/release.yml, bin/release-validate, and release artifact
contract tests

## [2026-08-06] Prove concurrency overlap and cross-session outcomes

**Action:** Replaced simultaneous-start race tests with deterministic barriers
that prove a competing database connection blocks while the first operation
holds its critical lock. Expanded the required self-hosted browser gate so the
original collaborator reads another member's reply, suspended sessions lose
access, restored accounts require a new sign-in, and recovery links reset
credentials once while rejecting replay.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260806T110000Z-deterministic-concurrency-browser-outcomes.md,
wiki/log.md

**Source:** deterministic concurrency integration tests and self-hosted
collaboration/instance-administration system tests

## [2026-08-06] Isolate Go checks from the Rails vendor directory

**Action:** Made the repository Go compatibility step explicitly use module
mode. The Rails/Bundler top-level `vendor/` tree is not a Go dependency vendor
tree, and Go 1.26 otherwise rejects it before compiling repository helpers.

**Pages updated:** wiki/api-cli.md,
wiki/log.d/20260806T101500Z-go-vendor-mode-isolation.md, wiki/log.md

**Source:** `.github/workflows/ci.yml`, `config/ci.rb`, and a reproduced Go 1.26
inconsistent-vendoring failure

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

## [2026-08-06] Isolate browser tests from precompiled assets

**Action:** Made the self-hosted collaboration matrix clobber ignored
precompiled assets before starting its source-backed Capybara server, preventing
a stale Propshaft manifest from shadowing current Stimulus controllers.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260806T093000Z-system-test-asset-isolation.md, wiki/log.md

**Source:** `script/release_test_matrix`, the retryable authentication-link
Playwright regression, and the observed precedence of
`public/assets/.manifest.json` over `app/javascript`

---
title: Release governance hardening
type: changelog
created: 2026-08-06
tags: [release, security, supply-chain, governance]
---

- Candidate archive preflight now parses the actual retained tar with
  `Gem::Package::TarReader` and permits only safe relative regular-file and
  directory members. Traversal paths, symlinks, hardlinks, devices, FIFOs, and
  other unsupported member types fail before extraction.
- The ORAS 1.3.2 registry preflight classifies an image as absent only for its
  exact requested-reference `failed to find ... not found` response or a
  single-line, anchored `manifest unknown` response. Ambiguous 404s, generic
  `not found` text, unrelated errors, and trailing output remain fatal.
- Publication authorization is exactly one direct-parent commit after the built
  source revision, with the exact path/status tuple: delete
  `docs/releases/PUBLICATION_BLOCKED.md`, add
  `docs/releases/evidence/public-evidence.json`, and modify
  `docs/releases/initial-release.md`; no additional changes are accepted.
- Both the workflow and `bin/release-validate` treat a dangling symlink at the
  publication-sentinel path as present, preserving the fail-closed blocker.
- The promotion job's default token is limited to `contents: read`,
  `attestations: write`, and `id-token: write`; repository and package mutation
  remains isolated to the dedicated release App token.
- `THIRD_PARTY_NOTICES.md` now matches the locked Thruster 0.1.23 dependency
  and the Alpine packages installed by `Dockerfile` through `apk`.

Publication remains externally blocked pending legal and Future Spin Ltd
chain-of-title approval; credential inventory, rotation, revocation, and history
disposition; live GitGuardian evidence; GitHub ruleset and protected-environment
configuration; an immutable public CLI tag; and retained exact-candidate image,
scan, SBOM, provenance, and release-note evidence. The publication sentinel must
remain until those gates are complete.

Related: [[self-hosting]], [[testing-and-ci]], [[gaps]].

---
date: 2026-08-06T08:30:00Z
scope: security-testing
---

Closed three silent-pass paths in the changed-security coverage gate with an
exact discovery oracle, full branch source ranges, and ignored-untracked
detection. Browser QA then exposed and verified a retryable invitation password
mismatch: local input errors now retain the tokenless invitation context and
the collaborator email control has a persistent label. Recovery coverage also
fixed canonical IPv6 authentication-link and deployment origins and moved token
consumption ahead of password and credential mutation so a lost race rolls
back cleanly. Contradictory string/symbol provider-proof keys now fail closed by
making an explicitly present string key authoritative.

The positive manifest includes the controllers that deliver the seven guarded
flows, and `CI / coverage` is a required default-branch check rather than a
manual-only handoff command.

Final correctness review also closed two misleading retry states. Account
recovery now retains its tokenless session context and returns 503 for
retryable authority or database failures, while terminal invalid links alone
clear that context. Whole-instance backup records a successful Compose stop
before post-stop inspection so a later inspection failure accurately warns
that the service remains stopped.

The final controller pass removed local-environment throttle bypasses in favor
of configured fail-closed stores, repaired retry-state invitation rendering,
made invitation mail enqueue outcome explicit, and prevented recovery issuance
from committing a one-time link before its HTML account-list prerequisite.
Instance administration now distinguishes invalid input from unavailable
infrastructure, and unexpected mutation results fail closed with 503 retry
guidance.

---
date: 2026-08-06T07:34:37Z
scope: authentication-security
---

Closed four browser authentication boundaries found during the source-release
review. Password login now uses Active Record's timing-safe `authenticate_by`
before active/suspended policy; one-time recovery and invitation presentations
are removed before Turbo snapshot caching and delivered with private no-store
headers; transient authentication-link database failures return retryable 503
responses while the scrubbed raw credential remains only in Stimulus memory;
and invitation OAuth callbacks require an exact local request-intent marker so
stale invitation context cannot capture ordinary provider sign-in. OmniAuth's
POST validator is also bound to Rails' real `:_csrf_token` session key, with a
positive Rails-form request-phase regression alongside missing/invalid-token
rejection.

---
date: 2026-08-06T07:15:00Z
scope: testing-and-ci
---

Corrected the final-image dependency probe to run through the image's Bundler
environment. A real ARM64 build, self-hosted preflight, Rails boot, and gem load
proved the packaged S3 and libvips runtimes were present; the previous bare Ruby
probe bypassed `BUNDLE_PATH` and produced a false missing-gem failure. The same
Bundler-aware command was reproduced successfully against the AMD64 image.

---
date: 2026-08-06T06:45:00Z
scope: testing-and-ci
---

Repaired the source-release coverage gate so it measures the contract it names. Coverage now starts before Rails boot, uses independent SaaS and explicit self-hosted processes, and applies a positive seven-domain source manifest to executable lines and branch arms changed from the trusted `origin/main` merge base. The changed security surface remains fixed at 100%; the legacy whole-application `MIN_COVERAGE` behavior is not used to weaken the release gate.

---
date: 2026-08-06T06:15:00Z
scope: self-hosting
---

The `system-collaboration` release matrix now owns a fixed test-only bootstrap token for its unclaimed-installation browser test and explicitly removes the token for claimed-installation tests. This makes the standalone matrix deterministic and preserves coverage of both bootstrap-required and post-claim operation. The self-hosted positive manifest also includes the instance-administration controller suite explicitly, so those routes cannot silently skip under the SaaS coverage process.

2026-08-06 — Made release immutability a live, fail-closed promotion precondition. The no-checkout promotion job uses its narrow release App's repository Administration read permission to require GitHub's exact enabled immutable-releases response before any registry, tag, attestation, or release mutation; disabled, missing, malformed, or unknown states stop the job while the post-publication release immutability check remains in place. GitGuardian source metadata likewise now requires both archived and deleted flags to be literal false. Candidate scanning pins GitGuardian's canonical instance plus its exact validated config path and gives Trivy/Syft explicit trusted configs with an empty Trivy ignore file, eliminating repository and runner scanner auto-configuration. See [[self-hosting]].

# Backup authenticity and runtime binding

- Added an independent operator-held HMAC key so a public age recipient cannot be used to forge an apparently valid Screenote backup.
- Required the authentication key to be a dedicated restricted single-link file outside every archived input and distinct from configuration, Compose, the age identity, and running application storage.
- Bound backup to the running container's exact secret files and local Docker storage volume before quiescing.
- Authenticated restore input before Docker mutation, retained the isolated-container recheck, and passed the age identity through an inherited descriptor so interrupted restore cannot leave private-key staging residue.
- Tightened release authorization to one direct-parent evidence commit, exact final-byte scanning, a post-approval live incident gate, strict Trivy exit/schema checks, and redacted S3 hook streams.

Related: [[self-hosting]], [[testing-and-ci]], [[decisions]].

# Release and recovery boundary preflights

- Made every publication rerun the no-checkout GitGuardian incident gate after retained-evidence authorization.
- Classified image, source tag, provenance attestation, and GitHub release together before the first mutation; only strict exact prefixes can resume.
- Signed the retained candidate provenance as a custom predicate, binding its certificate to the authorizing workflow SHA and its decoded statement to the built source identity.
- Bound backup and restore to the exact file-backed Compose secrets consumed by `screenote`, portable configuration-relative paths, and a sanitized Docker environment.

See [[self-hosting]], [[testing-and-ci]], and [[architecture]].

2026-08-06 — Made authentication-token character constraints portable between SQLite and PostgreSQL by expressing the allowlists with their shared `replace`, `substr`, and `length` functions. This prevents a self-hosted-generated `db/schema.rb` from embedding SQLite-only `GLOB` syntax that breaks a fresh SaaS PostgreSQL schema load. See [[schema-evolution]] and [[models/authentication-token]].

The preceding identity migration now also distinguishes the exact legacy, exact completed, and partial schema shapes. If its transactional work committed but Rails was interrupted before recording the migration version, rerunning verifies the completed data and records the version without repeating DDL; any non-exact partial shape fails closed for restore.

2026-08-06 — Expanded deterministic annotation author colors from 10 to 24 accessible palette entries after the multi-user collaboration matrix exposed a collision between two fixture collaborators. Canvas points, regions, draft markers, root comments, and replies continue to use the same identity-derived color token. See [[frontend-review-ui]].

2026-08-06 — Replaced the Debian slim production base with the digest-pinned Ruby 3.4.10 Alpine 3.24 multi-architecture index after the Debian candidate could not satisfy the release's zero Critical/High vulnerability policy. The runtime explicitly carries GNU core utilities and tar required by whole-instance restore, excludes separately tested transitional Go CLI sources and host-side Bundler caches, validates the exact base and Ruby version before release, and updates Thruster from 0.1.18 to 0.1.23 because the older binary embedded vulnerable Go dependencies. The container smoke gate now consumes an explicitly supplied immutable candidate instead of trying to rebuild under a digest reference. See [[self-hosting]] and [[architecture]].

# Self-hosted whole-instance operations

- Added fail-closed, age-encrypted whole-instance backup and restore commands for the four SQLite roles, operator configuration and secrets, and local or evidenced S3 blob state.
- Added strict manifest, filename, checksum, schema, image-chain, compose, storage-namespace, containment, and bounded-stream validation before restore publication.
- Added an in-container restore verifier, redacted diagnostics, adjacent-upgrade/rollback guidance, and an authentication-link prior-key rotation overlay.
- Established the initial uid/gid 1000 host contract and Docker `volume-nocopy` initialization for exact empty target volumes.
- Proved the supported local lifecycle against a final immutable image digest with real Docker: backup, stop/restart, four databases, blobs, annotations and replies, restore verification, and restored service startup all passed.

---
title: Source release governance and publication gates
type: changelog
created: 2026-08-06
tags: [source-available, release, security, gitguardian, supply-chain]
---

- Added the exact adapted O'Saasy license and Future Spin Ltd notice plus contributor, security, support, third-party, self-hosting, and release documentation.
- Removed encrypted Rails credentials from the current publication tree, ignored future encrypted payloads and keys, and recorded that authorized inventory, rotation, and history disposition are still blocking gates.
- Split the history-aware GitGuardian App, metadata-only paginated repository-incident check, and trusted source/image `ggshield` scans so none substitutes for another; the trusted incident gate explicitly reports to the PR head/test-merge SHA instead of relying on `pull_request_target`'s base-SHA check.
- Added no-bypass main/tag ruleset templates, full-SHA Action pins with provenance, checksum-pinned release tools, Dependabot coverage, redacted/restricted evidence contracts, and an executable publication sentinel.
- Added retained candidate and no-checkout protected promotion stages with exact source, OCI digest, SBOM, provenance, evidence, final-note, partial-object, and post-create readback bindings.
- Added offline adversarial incident-pagination tests and positive/negative artifact-contract fixtures; publication remains blocked on the documented external legal, credential, GitGuardian, repository-setting, CLI, and exact-candidate evidence.

## [2026-08-06] Keep existing-account passwords out of invitation acceptance

**Action:** Removed password verification for existing users from the reusable invitation endpoint. Existing invitees now authenticate through the ordinary rate-limited session flow and accept only through a matching signed-in identity; inline password creation remains available only when the invited address has no account. Added repeated-guess, multiple-link, controller, and real-browser admission regressions.

**Pages updated:** wiki/decisions.md, wiki/log.d/20260806T011900Z-invitation-password-oracle.md, wiki/log.md

**Source:** `app/services/project_invitations/accept.rb`, invitation acceptance UI/controller regressions, and self-hosted admission system coverage

## [2026-08-06] Make credential-cutover witness queries static

**Action:** Replaced the credential cutover's generic table/column/predicate SQL builder with a closed set of literal witness queries. The cutover still captures only one in-memory verification witness per credential kind, but its pre-migration reads can no longer be mistaken for or extended into an input-driven SQL surface.

**Resume boundary:** A rerun after the credential migration now applies and verifies every later migration before returning success. Merely finding the credential migration in `schema_migrations` cannot boot a successor with a partially upgraded schema.

**Atomic boundary:** PostgreSQL now holds one outer transaction across legacy-witness capture, the complete migration chain, stored-digest checks, and raw-credential runtime lookup proofs. Any migration or final verification failure restores both the legacy schema and reusable credentials for an evidence-preserving retry.

**Backup boundary:** The deployment command now stops and proves every predecessor process quiesced before it invokes a pre-reviewed, digest-pinned backup hook. The hook must create new private evidence bound to the command's timestamp and random challenge, an opaque database restore-point digest, both immutable revisions, and all four database roles; pre-stop evidence cannot authorize migration.

**Pages updated:** wiki/self-hosting.md, wiki/log.d/20260806T005800Z-static-cutover-queries.md, wiki/log.md

**Source:** `app/services/screenote/saas_credential_cutover.rb`, focused cutover tests, RuboCop, and a zero-warning Brakeman scan

---
title: Narrow self-hosted instance administration
date: 2026-08-06T00:30:00Z
---

- Added singleton administrator account metadata, suspension/restoration, comprehensive credential revocation, and atomic authority transfer without project access.
- Added issuer-bound, digest-only 15-minute account recovery with one-response presentation, tokenless exchange, single-use consumption, and 24-hour terminal retention.
- Added local-only recovery/transfer tasks, same-transaction audit records, credential-issuance serialization, independent-connection race coverage, and accessible narrow-viewport browser flows.
- Centralized browser identity replacement so invitation, password, OAuth, magic-link, recovery, registration, and bootstrap flows cannot leave a prior account's permanent session replayable.

---
title: Core and SaaS capability boundary
date: 2026-08-06T00:15:00+01:00
---

- Made self-hosted project and membership policy unlimited without consulting subscription or quota rows.
- Removed subscription, checkout, portal, Stripe webhook, hosted analytics, hosted legal, upgrade, and hosted-support surfaces from self-hosted routing and rendering.
- Kept the same SaaS revision's quotas, billing, Stripe, hosted operator, landing, and legal behavior intact.
- Replaced the generic `admin?` compatibility concept with an edition-bound `saas_operator?`; self-hosted instance authority remains installation-bound and separate.

---
title: Upload credentials leave request URLs
date: 2026-08-06
tags: [security, uploads, mcp, bearer]
---

# Upload credentials leave request URLs

**Action:** Changed the legacy MCP binary-upload contract to return a credential-free endpoint plus a separate five-minute, single-use bearer and content type. The upload controller accepts the credential only through `Authorization: Bearer`, rejects query credentials, and resolves the bearer before comparing the parent screenshot ID.

**Reason:** Authentication material must not enter proxy logs, browser history, request paths, query strings, referrers, or ordinary URL telemetry. The separate header also makes invalid credentials indistinguishable across existing and missing screenshot IDs.

**Source:** `app/controllers/api/screenshot_uploads_controller.rb`, `app/tools/create_screenshot_upload_tool.rb`, `app/tools/create_multi_viewport_screenshot_tool.rb`, controller/tool/system regressions, and [[controllers/api-controllers]].

---
title: Admission identity and authentication-token foundation
date: 2026-08-05T23:15:00Z
---

- Added fail-before-mutation identity preflights and canonical database constraints without losing SQLite user child graphs.
- Added active/suspended user state and durable pending/accepted/cancelled invitations.
- Added append-only installation audit events and digest-only, exact-purpose authentication-token rows with NULL-safe partial uniqueness on SQLite and PostgreSQL 16.

---
title: Atomic admission and authentication-link contract
date: 2026-08-05T22:50:00Z
---

- Froze one deadlock-safe authority order across bootstrap, invitation admission, membership removal, suspension, and recovery.
- Selected digest-only authentication-token rows with versioned HMAC re-derivation, explicit key IDs, fragment links, equivalent manual codes, and tokenless continuations.
- Fixed stable result vocabularies for claim, issue, accept, cancel, and issuer-wide cancellation before parallel U4 implementation.

## [2026-08-05] Bounded dynamic-client authorization

**Action:** Limited each user to 25 distinct active dynamically registered OAuth clients across authorization-code and device approval, serialized the check before credential issuance, preserved same-client reauthorization, and added deterministic global-capacity concurrency coverage.

**Decision:** A hard per-user active-client cap is safer than silently revoking a possibly active client because bearer use is not tracked precisely enough to select a trustworthy eviction candidate. Revoked credentials, expired non-refreshable credentials, expired grants, and expired device approvals stop consuming capacity; anonymous RFC 7591 registration remains idempotent and unused clients remain eligible for cleanup.

**Pages updated:** wiki/controllers/oauth-controllers.md, wiki/log.d/20260805T204155Z-dynamic-client-authorization-quota.md, wiki/log.md

**Source:** `app/services/oauth/dynamic_client_authorization_quota.rb`, `app/services/oauth/dynamic_client_registration.rb`, OAuth quota and concurrency regressions

## [2026-08-05] Authenticated principal and OAuth cutover

**Action:** Unified REST and MCP authorization around an immutable user/project principal, added server-owned OAuth project consent across authorization-code/device/refresh flows, serialized membership authority through credential creation and member removal, migrated OAuth and confidential-client secrets to digest-only storage, hardened dynamic registration, and made API-key actors durable without creator impersonation.
**Pages updated:** wiki/controllers/oauth-controllers.md, wiki/controllers/web-controllers.md, wiki/data-model.md, wiki/schema-evolution.md, wiki/gaps.md, wiki/models/api-key.md, wiki/models/annotation.md, wiki/models/annotation-comment.md, wiki/models/current.md, wiki/models/project-membership.md, wiki/decisions.md, wiki/log.md
**Source:** `app/services/authenticated_principal.rb`, `app/services/authority_lock.rb`, `app/services/project_memberships/remove.rb`, `app/controllers/oauth`, `app/services/oauth`, `config/initializers/doorkeeper.rb`, `config/initializers/fast_mcp.rb`, `db/migrate/20260805130000_add_api_key_issuers_and_annotation_actors.rb`, `db/migrate/20260805131000_harden_oauth_principals_and_token_secrets.rb`, U3 security and concurrency tests

# MCP principal and registry hardening

- Replaced the mutable MCP user/project/key/token tuple with one immutable `AuthenticatedPrincipal` in request-local state.
- Required exact orthogonal `mcp_read` or `mcp_write` authorization and complete safety metadata on every remotely registered tool.
- Replaced subclass discovery with an explicit 18-tool allowlist that excludes bootstrap, account-administration, recovery, transfer, publication, and secret-management actions.
- Preserved API-key project authority without impersonating the issuer and attributed supported annotation mutations to the key.
- Added request-reset, registry, scope, project-boundary, person-only-action, and API-key actor regression coverage.

Source: `app/models/current.rb`, `config/initializers/fast_mcp.rb`, `app/tools/**/*.rb`, `test/tools/mcp_security_contract_test.rb`

---
title: Active Storage upload commit lifecycle
type: changelog
created: 2026-08-05
tags: [self-hosting, active-storage, testing, transactions]
---

- Staged validated screenshot bytes in the selected storage service before attaching the Blob, so committed attachment metadata never depends on a closed request tempfile.
- Removed staged objects when a concurrent upload wins, persistence fails, or an outer transaction rolls back.
- Added a provider-free review test that denies every non-loopback request.
- Updated [[self-hosting]] and [[testing-and-ci]] with the transaction contract.

---
title: Deployment topology preflight
type: changelog
created: 2026-08-05
tags: [self-hosting, deployment, database, security]
---

- Added a standalone deployment preflight before `db:prepare`, preventing an edition change from selecting and initializing an unrelated database topology before persisted identity checks run.
- SaaS startup now refuses a mounted self-hosted primary, while self-hosted startup refuses retained SaaS database-role settings and verifies an existing SQLite installation's edition, storage service, storage namespace, and applicable bootstrap digest through a read-only connection.
- Added real entrypoint-ordering tests that use the production SQLite-versus-PostgreSQL topology boundary and prove identity drift stops before `db:prepare` can apply a pending migration.
- Updated [[self-hosting]] with the two-stage deployment identity contract.

---
title: Self-hosted Compose runtime modes
type: changelog
created: 2026-08-05
tags: [self-hosting, docker, secrets, readiness]
---

- Made the base Compose file the supported claimed local-storage mode, with the bootstrap credential isolated in a removable first-claim overlay.
- Added additive S3, SMTP, Google OAuth, GitHub OAuth, and Honeybadger overlays whose credentials are restricted files rather than environment values.
- Added local-only generic readiness across the four SQLite roles, persistent-volume writability, and selected storage configuration while preserving `/up` as liveness.
- Bounded Thruster request bodies at 30 MiB and added a final-image replacement/persistence smoke workflow.
- Updated [[self-hosting]] with the operational runtime contract.

---
title: Private media and processing recovery
type: changelog
created: 2026-08-05
tags: [self-hosting, active-storage, security, jobs]
---

- Disabled reusable Active Storage delivery and direct-upload routes in favor of project-membership-checked application media URLs.
- Unified signed and manifest image ingestion behind bounded byte, type, dimension, pixel-count, and decoder-concurrency validation.
- Added startup and recurring reconciliation for committed screenshot processing work that could not reach Solid Queue.
- Updated [[self-hosting]] with the concrete media and recovery contract.

## [2026-08-05] Deployment and provider boundary

**Action:** Implemented and reviewed the production configuration boundary shared by SaaS and the first self-hosted runtime.

**Decision:** Production requires an explicit edition, canonical origin, strong application secret, and mode-specific providers. Forwarded identity is honored only from configured immediate proxies; generated URLs and OAuth use the canonical origin. Optional self-hosted providers are inert unless explicitly and completely selected, S3 object keys use the persisted namespace prefix, rate limiting fails closed, and self-hosted monitoring exports only an error class plus opaque identifiers. A singleton `Installation` row persists edition, storage namespace, and bootstrap ownership state and is verified by the supported startup path.

**Pages updated:** `wiki/self-hosting.md`, `wiki/data-model.md`, `wiki/schema-evolution.md`, `wiki/models/user.md`, `wiki/controllers/web-controllers.md`

**Source:** `lib/screenote/deployment.rb`, `app/models/installation.rb`, `app/services/installations/prepare.rb`

## [2026-08-05] Self-hosted source release plan

**Action:** Recorded and adversarially reviewed the implementation-ready plan for publishing Screenote under the O'Saasy license with a prebuilt single-container self-hosted edition alongside the existing SaaS.

**Decision:** Future Spin Ltd is the intended Original Licensor, subject to chain-of-title and legal approval before publication. Self-hosted Screenote is an unlimited four-role SQLite runtime with local or S3-compatible private storage, restricted file-backed runtime secrets, atomic token-secured bootstrap, decentralized issuer-bound project invitations rather than a global Team entity, application-authorized screenshot delivery, and authenticated-encrypted local/S3 backup sets for sequential upgrades between retained immutable images. The SaaS bearer-secret migration uses a stopped-process maintenance cutover. One public repository carries explicitly classified core and SaaS capabilities; GitGuardian, image-vulnerability scanning, private security evidence, and resumable exact-digest promotion fail closed before publication.

**Pages updated:** `wiki/self-hosting.md`, `wiki/index.md`, `wiki/plans-and-initiatives.md`

**Source:** `docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md`

## [2026-08-04] Unsaved area editing

**Action:** Removed the duplicate custom outline from unsaved area comments, synchronized moved and resized Annotorious geometry into the pending form at pointer completion, verified edited geometry persists, and prevented small edit-handle movements from creating point comments.

**Decision:** Annotorious owns the only editable outline while an area is unsaved; Screenote's custom author marker begins after persistence. Edit gestures are classified separately from click-to-comment gestures.

**Source:** `app/javascript/controllers/annotorious_controller.js`, `test/system/annotations_test.rb`, `test/system/pages/annotations_page.rb`

# Project path navigation and compact thread controls

**Date:** 2026-08-03

**Action:** Replaced the raw page-name header with query-free project/path navigation, added current/all-project switching and path-prefix project filtering, compacted annotation actions into one row with a full-width unboxed reply composer, removed redundant page edit/delete actions, and made final-version deletion remove the empty page.

**Decision:** Stored captured paths retain their full identity, including query state, while review navigation presents only route hierarchy. Human-readable names, including URI punctuation, remain literal. Page lifecycle is owned by screenshot versions: a page persists while any version remains and is removed with the last version.

## [2026-08-03] Figma-style collaborative comments

**Action:** Moved initial annotation entry onto the screenshot, made click create a point and drag create an area, added deterministic author initials/colors, linked canvas markers with sidebar threads, and exposed replies in the saved-thread sidebar. Documented fullscreen collapsed-comment behavior and multi-user browser coverage.
**Pages updated:** wiki/frontend-review-ui.md, wiki/testing-and-ci.md, wiki/log.md
**Source:** `app/javascript/controllers/annotorious_controller.js`, annotation partials, review workspace styles, helper and system tests

## [2026-08-03] fullscreen comment controls

**Action:** Replaced the fullscreen X with a restore-size control and added an accessible comments icon that collapses and reopens the floating annotation sidebar. The sidebar remains open by default, its visibility survives Turbo frame updates while fullscreen, beginning an annotation reopens it before the comment form appears, and a later fullscreen entry resets it to open.
**Pages updated:** wiki/frontend-review-ui.md
**Source:** `app/views/screenshots/_workspace.html.erb`, `app/javascript/controllers/annotorious_controller.js`, `app/javascript/controllers/review_fullscreen_controller.js`, `app/assets/stylesheets/application.css`, `test/system/annotations_test.rb`

## [2026-08-03] fullscreen screenshot review

**Action:** Added an accessible fullscreen review mode that fits the active screenshot to the browser viewport without changing its aspect ratio, floats the annotation sidebar above the image, preserves Annotorious coordinate alignment and fullscreen state across annotation Turbo updates, and exits through either Escape or a visible X control.
**Pages updated:** wiki/frontend-review-ui.md, wiki/log.md
**Source:** `app/views/screenshots/_workspace.html.erb`, `app/javascript/controllers/review_fullscreen_controller.js`, `app/javascript/controllers/annotorious_controller.js`, `app/assets/stylesheets/application.css`, `test/system/annotations_test.rb`

## [2026-08-03] compact version selector

**Action:** Replaced the screenshot workspace's permanent version sidebar with a newest-first dropdown aligned to the right of the viewport switcher. The menu preserves page-scoped `version_id` links and compatible viewport state, overlays the workspace on laptops, and wraps to full width on narrow screens so more horizontal space remains available for annotations.
**Pages updated:** wiki/frontend-review-ui.md, wiki/log.md
**Source:** `app/views/pages/show.html.erb`, `app/views/screenshots/_workspace.html.erb`, `app/views/screenshots/_version_selector.html.erb`, `app/assets/stylesheets/application.css`, controller and browser regression tests

# Make screenshot review large enough to annotate

- Let screenshot review pages use an 1800px content ceiling while retaining
  the global 960px reading width elsewhere.
- Increased the standard 1280px test viewport's annotation canvas from 304px
  to 624px and added browser regression coverage for a 600px minimum.
- Normalized action-button border boxes and made Desktop, Tablet, and Mobile
  switcher segments equal width, with rendered-dimension browser assertions.

# Align page workspace action sizing

- Removed the version-only small-button modifier from edit and delete actions.
- Gave every populated-state header action the same fixed width while preserving
  wrapping on narrow screens.
- Added controller coverage requiring all five populated-state header actions
  to use the same base button size and direct-child structure.

# Patch Active Storage for CVE-2026-66066

- Updated Rails and Active Storage from 8.1.3 to 8.1.3.1.
- Recorded the native libvips 8.13 minimum required by the patched Active
  Storage implementation.
- Updated Loofah and rails-html-sanitizer to clear the current gem-audit gate.
- Verified all 796 application tests locally.

---
title: Guard overview representation URLs until thumbnail warming completes
date: 2026-07-28
---

Project cards and strips now consult the preloaded tracked variant records before
emitting named Active Storage representation URLs. Unwarmed page cards show a
thumbnail-processing placeholder and project strips omit their image, preserving
asynchronous `ScreenshotThumbnailJob` warming instead of allowing browser image
requests to process variants synchronously.

Thumbnail processing failures now retry up to three times, and retries skip
already tracked variants so partial generations resume without duplicate work.

Annotation writes also reject enum-valid viewports that the selected screenshot
does not have, preventing records hidden from every reachable workspace.

Playwright can now run at explicit 1x and 2x device scale factors; the page-card
system test proves the browser selects and requests the 480w and 960w candidates.

---
title: Make page workspaces direct, resilient, and fast
type: change
date: 2026-07-28
---

- Capture the active Annotorious drawing pointer so a selection can leave an image edge and resume when it returns.
- Normalize and clamp rectangle endpoints before persisting percentage geometry, including reverse drags and zero-area cleanup.
- Clean pointer listeners and capture across cancel, disconnect, image-less workspaces, and Turbo replacement.
- Add browser regression coverage for boundary, geometry, transient cleanup, and lifecycle behavior.
- Define fixed 480x270, 960x540, and 240x160 Active Storage overview variants and warm only the ready screenshot's current primary image after dimension processing commits.
- Revalidate image/blob generation and primary identity in a concurrency-limited thumbnail job so replacement, sibling, pending, failed, and unattached records remain untouched.
- Add a batchable `screenshots:warm_thumbnails` task that is dry-run by default and reports exact candidate, skipped, processed, and failed counts.
- Make `/pages/:id` the canonical review workspace, select its newest version
  immediately, and move newest-first version history into a text-only sidebar.
- Preserve exact page version and viewport state through project/snapshot cards,
  compatibility redirects, screenshot CRUD, annotations, and annotation comments.
- Replace overview-time ad-hoc transformations with named responsive variants,
  grid-aware image markup, and fixed-batch tracked-variant preloads.
- Bound both filtered and unfiltered eight-page project views to 14 application
  SQL statements and keep project-index query growth constant as thumbnail card
  counts increase.
- Document the Minitest, Playwright, overview-performance, and full-CI contracts
  in `wiki/testing-and-ci.md`.

## [2026-07-13T22:11:00Z] Screenshot review navigation and geometry

**Action:** Documented the project-card shortcut for a lone usable screenshot, sticky long-image annotation behavior, sidebar-local form scrolling with scroll-preserving comment focus, and Annotorious wrapper-based mobile centering and pin coordinates.
**Pages added:** wiki/frontend-review-ui.md
**Pages updated:** wiki/index.md, wiki/gaps.md, wiki/controllers/web-controllers.md
**Decision:** Responsive images remain variants of one logical screenshot. Review navigation skips the version grid only when exactly one usable logical screenshot exists, and all percentage annotation geometry is resolved against the visible image wrapper rather than the wider canvas.
**Source:** app/views/projects/show.html.erb, app/javascript/controllers/annotorious_controller.js, app/assets/stylesheets/application.css, regression tests in test/controllers/projects_controller_test.rb and test/system/annotations_test.rb

## [2026-07-13T21:49:53Z] CLI workflow REST parity

**Action:** Added OAuth REST project creation and idempotent project-scoped annotation resolution, including stable response/error contracts, owner membership and plan-quota enforcement, user/API-key resolution authorship, scoped project listing, scoped-token cleanup on project deletion, and regression coverage for read-only, API-key, stale-writer, structured-comment, project-scoped, missing-project, and cross-project authorization paths.
**Pages updated:** wiki/api-cli.md, wiki/commands.md, wiki/controllers/api-controllers.md, wiki/routes.md, wiki/gaps.md, wiki/models/project.md, wiki/models/annotation.md
**Decision:** Project creation is a user-level operation available only to user-scoped OAuth `mcp_write` tokens. Annotation resolution remains project-scoped, accepts API keys or OAuth `mcp_write`, and locks at the shared model boundary so stale REST, web, and legacy MCP writers do not duplicate the resolution audit comment. Project-scoped OAuth tokens list and authorize only their bound member project; deleting that project deletes its scoped grants/tokens rather than widening the credentials.
**Source:** `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/projects_controller.rb`, `app/controllers/api/v1/annotation_resolutions_controller.rb`, `app/models/project.rb`, `app/models/annotation.rb`, REST routes, controller integration tests, and model tests
**Integration proof:** A disposable local OAuth user drove the public CLI branch through project creation, project listing, screenshot upload, annotation listing, private `0600` crop export, comment creation, initial resolution, and an `already_resolved` replay against the real Rails server. The temporary user, OAuth application, token, project, and files were removed afterward.

## [2026-07-13T19:00:30Z] CLI/OAuth documentation audit

**Action:** Reconciled internal command, roadmap, and initiative pages with the shipped public CLI, OAuth-only onboarding, RFC 8628 device login, and manifest snapshot workflow. Corrected the old in-repository Go install path and removed future-facing recommendations to expand MCP.
**Pages updated:** wiki/commands.md, wiki/api-cli.md, wiki/roadmap.md, wiki/plans-and-initiatives.md
**Decision:** The public `ivankuznetsov/screenote-cli` repository is the supported agent and automation surface. MCP remains server-side compatibility until its separately scoped sunset; new CLI and integration work should not extend the MCP tool surface.
**Source:** merged server PR #41, public CLI PR #5, deployed `https://screenote.ai/` and `/help`, OAuth authorization-server metadata, and the public CLI README/Go module

## [2026-07-13T15:55:01Z] OAuth device authorization

**Action:** Added the RFC 8628 server grant, authenticated approval/denial UI, secure short-lived grant storage, additive discovery/registration metadata, and callback-free CLI help for SSH, tmux, and other headless sessions. Dynamic registration consumes the RFC top-level JSON shape without Rails wrapper noise and uses an OAuth-neutral fallback client name. Removed manual CLI token/API-key onboarding from public documentation; the CLI documents OAuth sign-in only.
**Pages updated:** wiki/api-cli.md, wiki/controllers/oauth-controllers.md, wiki/routes.md, wiki/data-model.md, wiki/schema-evolution.md
**Decision:** Device login prints a one-time code and authorization link for explicit approval on another device; a complete link never approves by itself. Raw device codes are SHA-256-only at rest, human codes have 50 bits of entropy and fail-closed throttled verification, grants use an indexed 10-minute absolute expiry plus scheduled cleanup after 15 minutes of terminal-error retention, and token polls start at five seconds. Existing browser-based PKCE remains the default.
**Source:** `app/controllers/oauth/device_*`, `lib/screenote_oauth/device_code_grant.rb`, `app/models/oauth_device_grant.rb`, `db/migrate/20260713160000_create_oauth_device_grants.rb`, OAuth integration/controller tests, and public help/README changes

## [2026-07-13T13:31:35Z] CLI-first website onboarding

**Action:** Replaced public MCP-first onboarding with verified standalone CLI installation and usage guidance across the landing page, dashboard banner, help, account surfaces, OAuth consent, legal pages, and welcome email. The help page also documents the current dashboard-only project creation and web-only annotation resolution boundaries instead of overstating CLI parity.
**Pages updated:** wiki/active-areas.md, wiki/api-cli.md, wiki/controllers/web-controllers.md, wiki/gaps.md
**Decision:** The standalone CLI is the canonical public agent interface. The existing MCP runtime and OAuth scope identifiers remain unchanged because transport retirement is a separate effort.
**Source:** `app/views/static_pages`, `app/views/projects/index.html.erb`, account and OAuth views, welcome mailer views, and the public `screenote-cli` install/command contract

---
title: API key production schema repair
type: log
date: 2026-07-12
---

# API key production schema repair

**Action:** Documented and repaired historical API-key schema drift discovered by the production CLI OAuth smoke. A new irreversible forward migration converts any legacy plaintext tokens to SHA-256 digests and prefixes, preserves already-secure fresh databases, fails closed on unknown schemas, and bounds PostgreSQL lock acquisition. Added isolated SQLite coverage plus a dedicated PostgreSQL 16 CI lane for the production-specific migration path.

**Pages updated:** `wiki/models/api-key.md`, `wiki/schema-evolution.md`, and this log fragment.

**Source:** Production schema metadata, PR #3 and PR #4 history, `.github/workflows/ci.yml`, `db/migrate/20260212071431_create_api_keys.rb`, deleted migration `20260212151018_add_token_digest_to_api_keys.rb`, `app/models/api_key.rb`, and `app/services/api/bearer_authenticator.rb`.

---
title: Snapshot processing recovery and public CLI contract gate
type: log
date: 2026-07-12
---

# Snapshot processing recovery and public CLI contract gate

**Recovery:** An unchanged manifest replay now schedules dimension processing for every attached pending ScreenshotImage. This repairs the cross-database failure window where the application attachment commits but Solid Queue enqueue fails. Concurrency is keyed by ScreenshotImage and attachment blob generation, so same-blob retries deduplicate without dropping replacement analysis; stale jobs recheck the generation before writing dimensions.

**Contract:** The public CLI owns `testdata/contracts/snapshot-digests-v1.json`. Rails loads that exact file from a separately checked-out CLI repository, executes its primitive manifest/group vectors, and submits its normalized semantic manifest through `Snapshots::PrepareUpload`; no digest literals are copied into private tests.

**CI:** Pull requests pin an immutable public CLI commit as the supported v1 candidate. A separate scheduled/manual workflow checks public CLI `main` without making a moving branch a service merge gate.

**Coverage:** A forced queue-adapter failure proves the attachment remains pending and a byte-identical manifest replay enqueues recovery. Ready and unattached images remain no-op replays.

**Source:** `app/services/snapshots/ensure_processing.rb`, `app/services/snapshots/prepare_upload.rb`, `app/jobs/screenshot_dimension_job.rb`, service/contract tests, and GitHub Actions workflows.

---
title: Authenticated snapshot image upload
type: log
date: 2026-07-10
---

# Authenticated snapshot image upload

**Action:** Added the project-scoped API v1 raw-body upload resource for prepared ScreenshotImages.

**Security:** Bodies stream through a bounded, auto-unlinked temporary file. Actual MIME is detected from bytes and must be PNG/JPEG matching both the request header and prepared type; computed SHA-256 must match the prepared identity. Error responses contain only stable codes and context, never bytes, bearer credentials, or client-local paths.

**Idempotency:** Row locking permits exactly one attachment. Identical retries return success without another blob or job; failed processing retries reuse the attachment, return to pending, and enqueue one new dimension job. Concurrent coverage proves one attachment and one initial processing job.

**Compatibility:** OAuth `mcp_write` and project API keys are supported. The existing signed-token MCP upload controller and its behavior are unchanged.

**Source:** `app/controllers/api/v1/screenshot_images_controller.rb`, `app/services/snapshots/attach_image.rb`, `app/serializers/api/v1/contract_serializer.rb`, `config/routes.rb`, and focused controller/service/integration tests.

---
title: Snapshot REST preparation and recovery
type: log
date: 2026-07-10
---

# Snapshot REST preparation and recovery

**Action:** Added authenticated API v1 prepare and show resources for manifest-backed project snapshots.

**Contract:** The service validates version, commit, explicit-offset timestamp, bounded flat entries, page/title groups, unique viewports, expected PNG/JPEG types, content hashes, opaque file-reference hashes, and the aggregate length-prefixed manifest digest before mutation.

**Recovery:** Identical and concurrent calls converge on one transactionally created graph. Replay verifies stored metadata, group membership, viewport membership, content SHA, and expected type; mismatch returns `manifest_conflict`. Responses expose stable IDs, aggregate/image state, and a snapshot-filtered review URL without local file references.

**Authorization:** API keys stay bound to their project. OAuth create requires `mcp_write`, show requires `mcp_read`, and project membership remains mandatory.

**Source:** `app/controllers/api/v1/snapshots_controller.rb`, `app/services/snapshots/prepare_upload.rb`, `app/serializers/api/v1/contract_serializer.rb`, `config/routes.rb`, and snapshot REST/service/integration tests.

---
title: Public CLI manifest identity
type: log
date: 2026-07-10
---

# Public CLI manifest identity

**Action:** Added nullable manifest, entry, image content SHA-256, and expected content-type identities for resumable CLI snapshot preparation.

**Behavior:** Legacy and MCP-created rows remain valid without digests. Manifest-backed snapshots require uniquely identified screenshot entries and content-bound ScreenshotImages with an expected PNG/JPEG type. Snapshot state is derived as awaiting upload, processing, failed, or ready from real child attachment and processing state.

**Integrity:** Partial unique indexes protect project snapshot and snapshot entry identities without changing repeated git-commit capture semantics. Existing snapshot deletion nullification and same-project validation remain unchanged.

**Source:** `db/migrate/20260710120000_add_manifest_identity_to_snapshots.rb`, `app/models/snapshot.rb`, `app/models/screenshot.rb`, `app/models/screenshot_image.rb`, and focused model tests.

---
timestamp: 2026-07-09T14:56:01Z
slug: local-ci-bootstrap
---

**Action:** Improved local CI bootstrap and dependency checks.

**Files changed:** `bin/ci`, `bin/setup`, `bin/check_coverage`, `config/ci.rb`, `.github/workflows/ci.yml`, `.gitignore`, `Gemfile.lock`, `test/test_helper.rb`, `test/jobs/screenshot_dimension_job_test.rb`, `test/services/annotation_crop_service_test.rb`

**Notes:** `bin/ci` now installs missing gems before Rails boot, stores bundles in `vendor/bundle`, runs whitespace checks, keeps GitHub push CI aligned to `main`, and runs Go tests when `go.mod` is present. Set `REQUIRE_COVERAGE=true` to run Rails tests with SimpleCov and fail below 100% line or branch coverage via `bin/check_coverage`; coverage runs force one worker for stable measurement, and `PARALLEL_WORKERS` can override normal Rails test parallelism. The lockfile was refreshed for current `bundler-audit` advisories, Brakeman freshness, and Playwright protocol compatibility. GitHub CI installs `libvips` and compatible Playwright browsers for system tests, runs Capybara against its in-process Rails server when `CAPYBARA_RUN_SERVER=true`, serializes system tests with `PARALLEL_WORKERS=1`, and caps the system-test job at 15 minutes. System fixtures now include the seed-equivalent `test@screenote.app`, `free@screenote.app`, and `Demo Project` records expected by browser tests. Browser API/MCP helpers derive the live Capybara server URL, invitation tests inspect test mail deliveries instead of letter_opener files, and mailer preview assertions live in mailer tests; local image-processing tests skip with an explicit message when the system library is unavailable.

---
timestamp: 2026-07-09T14:54:14Z
slug: mcp-test-token-project-scope
---

**Action:** Documented the non-interactive MCP test-token endpoint and its project-scoped OAuth semantics.

**Pages updated:** `wiki/controllers/oauth-controllers.md`, `wiki/mcp-tools.md`, `wiki/routes.md`

**Source:** `app/controllers/oauth/test_tokens_controller.rb`, `config/initializers/fast_mcp.rb`, `app/tools/application_tool.rb`, `app/tools/list_projects_tool.rb`, `app/tools/create_project_tool.rb`, and `test/controllers/oauth/test_tokens_controller_test.rb`.

## [2026-07-08T19:42:13Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed command, REST API controller, route, MCP/CLI boundary, and CLI wiki coverage after the `add-a-go-cli-for-260708-edec` branch updated wiki-facing command/API surface documentation.
**Pages updated:** `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`
**Pages already current:** `wiki/api-cli.md`, `wiki/index.md`, `wiki/gaps.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `config/routes.rb`, `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/*`, `app/serializers/api/v1/contract_serializer.rb`, `app/services/api/v1/project_scope.rb`, `cmd/screenote`, `internal/cli`, and `internal/screenote`.
**Notes:** Kept wiki edits in the main checkout only. Used `qmd search` and source inspection; did not run `qmd update` or `qmd embed`.

## [2026-07-08T19:22:29Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual finalizer commit changed only branch-local wiki files, deleted branch-local log fragments/maintenance coverage, and simplified some CLI/API wiki wording.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/errors.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** The configured cross-project wiki path `/home/asterio/wikis/master/wiki` is absent and `qmd search` returned no matching results for the CLI/API refresh query. The branch-local wiki maintenance/log rollback still conflicts with the main-checkout wrapper instruction to add fragments and avoid direct compiled `wiki/log.md` edits.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T19:20:03Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` finalizer commit changed branch-local wiki files and removed branch-local log fragments/maintenance coverage without changing the committed CLI/API source behavior.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:README.md`, `git show add-a-go-cli-for-260708-edec:cmd/screenote/main.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/*`, `git show add-a-go-cli-for-260708-edec:internal/screenote/*`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, `git show add-a-go-cli-for-260708-edec:app/services/api/v1/project_scope.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path plus default fallback paths were absent. The branch-local maintenance/log rollback still conflicts with the main-checkout fragment-based refresh instructions, so this refresh kept the main checkout's fragment policy and did not edit compiled `wiki/log.md`.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T19:16:02Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual 6-review commit removed or simplified branch-local wiki details without changing the committed CLI/API source behavior.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/screenshots_controller.rb`, and current main-checkout wiki pages.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path plus default fallback paths were absent. The branch-local maintenance/log rollback still conflicts with the main-checkout fragment-based log policy.
**Notes:** Kept edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T19:14:11Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual 6-review commit changed only branch-local wiki files while the committed CLI/API source tree still supports the richer documented command and REST API surface.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `README.md`, `cmd/screenote/main.go`, `internal/cli/annotation.go`, `internal/cli/screenshot.go`, `internal/cli/root.go`, `internal/cli/errors.go`, `internal/screenote/client.go`, `internal/screenote/types.go`, `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/*`, `app/serializers/api/v1/contract_serializer.rb`, and `config/routes.rb`.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path remained unavailable. The branch-local wiki maintenance/log rollback conflicts with the main-checkout wrapper instruction to add fragments and avoid direct compiled `wiki/log.md` edits.
**Notes:** Kept edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T18:54:31Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` pass-02 review-fix commit edited CLI/API wiki wording, removed branch-local `wiki/log.d/` fragments, deleted branch-local `wiki/llm-wiki-maintenance.md`, and rewrote branch-local compiled `wiki/log.md`.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:cmd/screenote/main.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, `git show add-a-go-cli-for-260708-edec:app/services/api/v1/project_scope.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** The configured cross-project wiki path and default fallback paths were absent, and `qmd search` returned no matching project-wiki results. The branch-local wiki maintenance/log policy still conflicts with the main-checkout wrapper instructions, so this refresh kept the main checkout's fragment-based log policy and did not edit compiled `wiki/log.md`.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T18:51:56Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout CLI/API wiki coverage after the `add-a-go-cli-for-260708-edec` review-pass commit changed wiki-facing CLI/API wording and removed wiki maintenance artifacts from its own tree.
**Pages updated:** `wiki/api-cli.md`
**Pages verified current:** `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/gaps.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:README.md`, `git show add-a-go-cli-for-260708-edec:cmd/screenote/main.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/root.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/commands_test.go`, `git show add-a-go-cli-for-260708-edec:internal/screenote/client.go`, `git show add-a-go-cli-for-260708-edec:internal/screenote/types.go`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, and `git show add-a-go-cli-for-260708-edec:config/routes.rb`.
**Uncertainty:** The configured cross-project wiki path and default fallback paths were absent; `qmd search` returned no matching project-wiki results. The branch tree still conflicts with current main-checkout instructions on `wiki/log.d/` fragments and compiled `wiki/log.md`, so this refresh followed the wrapper instruction to add a fragment and avoid editing compiled `wiki/log.md`.
**Notes:** Kept wiki edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T18:47:28Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after inspecting the `add-a-go-cli-for-260708-edec` branch wiki commit and the committed REST/Go CLI source tree it documents.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `git show add-a-go-cli-for-260708-edec:config/routes.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/base_controller.rb`, `git show add-a-go-cli-for-260708-edec:app/controllers/api/v1/*`, `git show add-a-go-cli-for-260708-edec:app/serializers/api/v1/contract_serializer.rb`, `git show add-a-go-cli-for-260708-edec:internal/cli/annotation.go`, `git show add-a-go-cli-for-260708-edec:internal/cli/screenshot.go`, and current main-checkout wiki pages.
**Uncertainty:** The branch commit deletes `wiki/log.d/` fragments and `wiki/llm-wiki-maintenance.md` in its own tree, but current main-checkout instructions require log fragments and wrapper-owned compiled `wiki/log.md`; recorded this policy mismatch in `wiki/gaps.md`.
**Notes:** Kept edits under `/home/asterio/Dev/screenote/wiki/` only. Used `qmd search`; did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.

## [2026-07-08T18:23:02Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed wiki coverage after the `add-a-go-cli-for-260708-edec` branch corrected Go CLI annotation aggregation, usage exits, upload content types, compact JSON output, and CLI docs.
**Pages created:** `wiki/api-cli.md`
**Pages updated:** `wiki/index.md`, `wiki/gaps.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, committed `internal/cli/annotation.go`, `internal/cli/root.go`, `internal/cli/screenshot.go`, `internal/cli/commands_test.go`, and committed `wiki/api-cli.md`
**Notes:** Did not edit compiled `wiki/log.md`; this fragment is for the post-commit wrapper to compile. Did not run `qmd update` or `qmd embed`.

## [2026-07-08T15:34:48Z] refresh

**Action:** Refreshed project wiki against current LLM-wiki automation and recent git history.
**Pages created:** `wiki/llm-wiki-maintenance.md`
**Pages updated:** `wiki/index.md`, `wiki/gaps.md`
**Pages unchanged after source verification:** core architecture/model/controller/MCP pages; recent commits after the prior refresh changed LLM-wiki automation and context files, not application source behavior.
**Cross-project wiki:** `.llm-wiki/config.json` still points at `/home/asterio/wikis/master/wiki`, but that path and the default fallback main wiki paths were absent on this machine during refresh.
**QMD:** Used `qmd search` only; did not run `qmd update` or `qmd embed`.
**Source:** `.llm-wiki/config.json`, `AGENTS.md`, `CLAUDE.md`, `.llm-wiki/refresh-wiki.sh`, `.llm-wiki/post-commit-refresh.sh`, `.llm-wiki/compile-log.sh`, `.claude/settings.json`, recent `git log`, source inventory under `app/`, `config/`, `db/`, `plans/`, and `todos/`.
<!-- END GENERATED WIKI LOG FRAGMENTS -->

## 2026-04-10 -- Bootstrap

**Author:** Claude (LLM wiki bootstrap)
**Scope:** Full wiki creation from codebase analysis

### Pages created (25 total):

**Architecture (7):**
- `wiki/architecture.md` -- High-level app structure
- `wiki/data-model.md` -- ER diagram and all tables
- `wiki/schema-evolution.md` -- 21 migrations across 4 phases
- `wiki/routes.md` -- Complete route surface area
- `wiki/gems.md` -- Gem choices with rationale
- `wiki/decisions.md` -- 12 lightweight ADRs from git history
- `wiki/active-areas.md` -- Recent development activity

**Models (13):**
- `wiki/models/user.md`
- `wiki/models/project.md`
- `wiki/models/page.md`
- `wiki/models/screenshot.md`
- `wiki/models/annotation.md`
- `wiki/models/annotation-comment.md`
- `wiki/models/api-key.md`
- `wiki/models/project-membership.md`
- `wiki/models/project-invitation.md`
- `wiki/models/subscription.md`
- `wiki/models/session.md`
- `wiki/models/current.md`
- `wiki/models/application-record.md`

**Controllers (3):**
- `wiki/controllers/web-controllers.md` -- 14 web controllers
- `wiki/controllers/api-controllers.md` -- 3 API controllers
- `wiki/controllers/oauth-controllers.md` -- 3 OAuth controllers

**Services (1):**
- `wiki/services/annotation-crop-service.md`

**Meta (2):**
- `wiki/gaps.md` -- Known documentation gaps
- `wiki/index.md` -- Full page catalog

### Sources read:
- `db/schema.rb` (21 migrations, 13+ tables)
- 13 model files in `app/models/`
- 24 controller files in `app/controllers/`
- 1 service file in `app/services/`
- `config/routes.rb`
- `Gemfile`
- `CLAUDE.md`
- 109 git commits analyzed

### CLAUDE.md updated:
- Appended wiki section with structure, rules, and session protocols

## [2026-04-11] ingest

**Action:** Ingested plans/ (4 files) and todos/ (151 files) into wiki
**Pages created:** plans-and-initiatives.md, technical-debt.md, roadmap.md
**Pages updated:** active-areas.md, gaps.md, index.md
**Source:** plans/ and todos/ directories

## [2026-05-14T16:53:28Z] bootstrap

**Action:** Managed llm-wiki bootstrap from codebase and Hive registry.
**Pages created:** wiki/commands.md, wiki/dependencies.md
**Pages updated:** wiki/index.md, wiki/log.md, wiki/gaps.md, .llm-wiki/config.json, AGENTS.md, CLAUDE.md, .claude/settings.json
**QMD:** qmd missing
**Scheduler:** files written; systemctl enable failed for llm-wiki-screenote-a932fe24.timer
**Post-commit hook:** /home/asterio/Dev/screenote/.githooks/post-commit
**Source:** Codebase read + git history

## [2026-05-14T17:07:38Z] refresh

**Action:** Refreshed stale wiki pages against current source, recent git history, configured master wiki, plans, and todos.
**Pages created:** wiki/models/screenshot-image.md, wiki/mcp-tools.md
**Pages updated:** wiki/data-model.md, wiki/models/screenshot.md, wiki/models/annotation.md, wiki/services/annotation-crop-service.md, wiki/architecture.md, wiki/routes.md, wiki/controllers/api-controllers.md, wiki/controllers/web-controllers.md, wiki/schema-evolution.md, wiki/decisions.md, wiki/active-areas.md, wiki/roadmap.md, wiki/plans-and-initiatives.md, wiki/technical-debt.md, wiki/gaps.md, wiki/index.md, wiki/log.md
**Gaps found:** jobs scheduling documentation, todo/source status drift, remaining MCP delete/status/batch tools, ScreenshotImage transition cleanup
**Cross-project wiki:** searched `/home/asterio/wikis/master/wiki` and QMD results before editing
**QMD:** `screenote` collection already existed; `qmd embed` completed with CPU fallback but embedded 0 chunks and reported 3 failed chunks; `qmd update` failed with `SQLITE_READONLY`
**Source:** `git log --since=2026-04-20`, `db/schema.rb`, `app/models`, `app/controllers`, `app/tools`, `app/services`, `config/routes.rb`, `config/initializers/fast_mcp.rb`, `plans/`, `todos/`

## [2026-05-14T17:26:52Z] llm-wiki validation

**Action:** Validated managed llm-wiki bootstrap and scheduled maintenance after Hive registry bootstrap.
**Headless agent:** Codex (`.llm-wiki/config.json` has `headless_agent: "codex"`).
**Context:** `AGENTS.md` and `CLAUDE.md` contain the managed LLM WIKI block; Claude `SessionStart` prints `wiki/index.md` and recent `wiki/log.md`.
**QMD:** `qmd 2.1.0` collection update, embed, and `qmd search` succeeded for this collection after the scheduled refresh test. QMD attempted GPU first and fell back to CPU because Vulkan headers are missing.
**Scheduler:** `llm-wiki-screenote-a932fe24.timer` is enabled and active under `systemctl --user`; next run is scheduled for 2026-05-15 18:03:41 BST.
**Maintenance scripts:** `.llm-wiki/refresh-wiki.sh` and `.llm-wiki/post-commit-refresh.sh` use bounded Codex and qmd timeouts and tell headless Codex not to run `qmd update` or `qmd embed` itself.
**Source:** `systemctl --user list-timers`, `qmd update`, `qmd embed`, and collection-scoped `qmd search`.

## [2026-05-14] snapshot model

**Action:** Documented the Snapshot model and project-page snapshot filtering data model.
**Pages created:** wiki/models/snapshot.md
**Pages updated:** wiki/data-model.md, wiki/models/project.md, wiki/models/screenshot.md, wiki/index.md
**Source:** Snapshot implementation in app/models, db/schema.rb, and project page controller/view changes

## [2026-05-15] snapshot review hardening

**Action:** Clarified snapshot duplicate-commit semantics, UTC-stable labels, future timestamp validation, and model-owned project-page snapshot queries.
**Pages updated:** data-model.md, models/project.md, models/snapshot.md
**Source:** Review pass 03 fixes for the snapshot feature

## [2026-07-08] OAuth-first CLI and REST OAuth auth

**Action:** Updated API/CLI docs for OAuth-first CLI authentication and REST v1 dual bearer authentication.
**Pages updated:** wiki/api-cli.md, wiki/controllers/api-controllers.md, wiki/routes.md, wiki/log.md
**Source:** `internal/cli`, `internal/screenote`, `app/controllers/api`, `app/services/api/bearer_authenticator.rb`, controller tests

## [2026-07-09] OAuth CLI review hardening

**Action:** Hardened the OAuth CLI review findings: bounded every default HTTP path, kept saved login credentials aligned with the configured server, preserved JSON-only output when browser launch fails, masked bearer tokens from `screenote config`, and enforced owner-only permissions on existing config files.
**Pages updated:** wiki/api-cli.md, wiki/log.md
**Source:** `internal/cli`, `internal/config`, `internal/screenote`, Go regression tests

## [2026-07-09] snapshot review and current-main integration

**Action:** Re-reviewed project snapshots against current main, preserved pending-only and failed-only pages in the unfiltered project view, made empty snapshot-filter states accurate, required explicit-offset MCP timestamps, echoed snapshot linkage in capture responses, regenerated the schema so its 40-character git commit limit matches the migration, made the snapshot system test target Capybara's actual in-process server, and removed unrelated historical planning/todo artifacts from the PR.
**Pages updated:** wiki/index.md, wiki/schema-evolution.md, wiki/mcp-tools.md, wiki/models/project.md, wiki/models/snapshot.md, wiki/log.md
**Source:** `app/models/project.rb`, `app/tools/create_snapshot_tool.rb`, `app/tools/create_multi_viewport_screenshot_tool.rb`, project views, migrations, and regression tests

## [2026-07-13] public help command parity

**Action:** Updated the public help workflow after production verification so CLI project creation, annotation crop extraction, and idempotent annotation resolution are documented instead of the superseded dashboard-only and web-only limits.
**Pages updated:** wiki/active-areas.md, wiki/log.md
**Source:** `app/views/static_pages/_help_quick_start.html.erb`, `app/views/static_pages/_help_cli.html.erb`, public CLI merge `c28ac8b`

## [2026-08-05] Active Storage upload commit lifecycle

**Action:** Staged validated screenshot bytes before attachment commit, cleaned unused and rolled-back objects, kept upload temporary files block-scoped, and added a self-hosted Playwright review test with external browser requests denied.
**Pages updated:** wiki/self-hosting.md, wiki/testing-and-ci.md, wiki/gaps.md, wiki/log.md
**Source:** `app/services/snapshots/attach_image.rb`, `test/system/application_system_test_case.rb`, `test/system/self_hosted_offline_review_test.rb`

## [2026-08-05] Complete pre-migration installation identity gate

**Action:** Extended the read-only deployment preflight to reject self-hosted storage-service, storage-namespace, and unclaimed-bootstrap drift before `db:prepare`, with database-digest and entrypoint-ordering regressions proving pending migrations cannot run on a mismatched primary.
**Pages updated:** wiki/self-hosting.md, wiki/log.d/20260805T174138Z-deployment-topology-preflight.md, wiki/log.md
**Source:** `lib/screenote/deployment_preflight.rb`, `test/lib/screenote/deployment_preflight_test.rb`, `test/integration/self_hosted_secret_configuration_test.rb`

## [2026-08-05] Transaction-safe dimension handoff

**Action:** Deferred production dimension jobs until the attachment's outer transaction commits, preventing replacement workers from observing and discarding stale attachment state; added explicit commit, rollback, and production-boot contracts.
**Pages updated:** wiki/self-hosting.md, wiki/log.md
**Source:** `app/jobs/screenshot_dimension_job.rb`, `test/jobs/screenshot_dimension_job_transaction_test.rb`, `test/integration/production_boot_test.rb`

## [2026-08-05] MCP principal and registry hardening

**Action:** Replaced mutable MCP identity fields with one immutable authenticated principal, enforced exact per-tool scopes and complete safety hints, registered only an explicit approved tool allowlist, and preserved API-key actor provenance without creator impersonation.
**Pages updated:** wiki/mcp-tools.md, wiki/models/current.md, wiki/log.d/20260805T200000Z-mcp-principal-registry.md, wiki/log.md
**Source:** `app/models/current.rb`, `config/initializers/fast_mcp.rb`, `app/tools/**/*.rb`, MCP security regression tests

## [2026-08-05] Authenticated principal and OAuth cutover

**Action:** Unified REST and MCP authorization around an immutable user/project principal, added server-owned OAuth project consent across authorization-code/device/refresh flows, serialized membership authority through credential creation and member removal, migrated OAuth and confidential-client secrets to digest-only storage, hardened dynamic registration, and made API-key actors durable without creator impersonation.
**Pages updated:** wiki/controllers/oauth-controllers.md, wiki/controllers/web-controllers.md, wiki/data-model.md, wiki/schema-evolution.md, wiki/gaps.md, wiki/models/api-key.md, wiki/models/annotation.md, wiki/models/annotation-comment.md, wiki/models/current.md, wiki/models/project-membership.md, wiki/decisions.md, wiki/log.md
**Source:** `app/services/authenticated_principal.rb`, `app/services/authority_lock.rb`, `app/services/project_memberships/remove.rb`, `app/controllers/oauth`, `app/services/oauth`, `config/initializers/doorkeeper.rb`, `config/initializers/fast_mcp.rb`, U3 migrations and security/concurrency tests

## [2026-08-05] Request-bound MCP transport isolation

**Action:** Retired FastMCP's globally broadcasting legacy SSE/messages endpoints in favor of request-bound POST `/mcp`, bounded invalid-bearer work with a fail-closed pre-authentication IP limiter, and made project listing recheck current OAuth membership before serialization.
**Pages updated:** wiki/mcp-tools.md, wiki/log.md
**Source:** `config/initializers/fast_mcp.rb`, `app/tools/list_projects_tool.rb`, MCP transport and tool regressions

## [2026-08-05] Bounded dynamic-client authorization

**Action:** Limited each user to 25 distinct active dynamically registered OAuth clients across authorization-code and device approval, serialized the check before credential issuance, preserved same-client reauthorization, and added deterministic global-capacity concurrency coverage.
**Pages updated:** wiki/controllers/oauth-controllers.md, wiki/log.d/20260805T204155Z-dynamic-client-authorization-quota.md, wiki/log.md
**Source:** `app/services/oauth/dynamic_client_authorization_quota.rb`, `app/services/oauth/dynamic_client_registration.rb`, OAuth quota and concurrency regressions

## [2026-08-05] MCP validation order and dependency redaction

**Action:** Moved canonical path, method, IP-policy, and origin-policy rejection ahead of the pre-authentication IP counter while keeping that counter ahead of bearer lookup; normalized FastMCP backtrace errors, suppressed dependency payload logging, and gave every system test a fresh in-memory limiter cache instead of the test environment's fail-closed NullStore.
**Pages updated:** wiki/mcp-tools.md, wiki/testing-and-ci.md, wiki/log.md
**Source:** `config/initializers/fast_mcp.rb`, `test/tools/mcp_auth_test.rb`, `test/system/application_system_test_case.rb`, MCP Playwright regressions

## [2026-08-05] Verifiable legacy API-key issuer attribution

**Action:** Restricted legacy issuer backfill to projects whose recorded creator is also the unique current owner, failing before schema mutation when project custody is missing or ambiguous, and added runtime proof that migrated OAuth token digests remain lookup- and refresh-compatible.
**Pages updated:** wiki/schema-evolution.md, wiki/models/api-key.md, wiki/log.md
**Source:** `db/migrate/20260805130000_add_api_key_issuers_and_annotation_actors.rb`, isolated migration tests, OAuth flow integration tests

## [2026-08-05] Block unsafe rolling credential migration

**Action:** Recorded the existing Kamal post-deploy migration hook as a release blocker and assigned an executable stop-the-world OAuth credential cutover, refusal guard, backup/restore boundary, and overlap smoke proof to U7/U9.
**Pages updated:** `docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md`, wiki/gaps.md, wiki/log.md
**Source:** `.kamal/hooks/post-deploy`, migration `20260805131000`, PostgreSQL upgrade review

## [2026-08-05] Correct legacy API-key issuer handling

**Action:** Superseded the earlier attribution claim after confirming that current ownership cannot prove historical key issuance. The migration now revokes every preexisting key without assigning an issuer, preserves those rows as unknown-issuer audit actors, and requires every active key to carry immutable issuer provenance.
**Pages updated:** wiki/schema-evolution.md, wiki/models/api-key.md, wiki/data-model.md, wiki/log.md
**Source:** `db/migrate/20260805130000_add_api_key_issuers_and_annotation_actors.rb`, `app/models/api_key.rb`, migration and authentication regressions

## [2026-08-05] Preserve SQLite API-key actor links during migration

**Action:** Prevented SQLite parent-table rebuilds from firing legacy `ON DELETE SET NULL` or cascade actions by detaching affected child foreign keys through the alteration window, restoring restrictive constraints afterward, and verifying row and API-key attribution counts before commit.
**Pages updated:** wiki/schema-evolution.md, wiki/log.md
**Source:** `db/migrate/20260805130000_add_api_key_issuers_and_annotation_actors.rb`, SQLite and PostgreSQL migration regressions for comment and resolution actors

## [2026-08-05] Freeze atomic admission and authentication-link contract

**Action:** Replaced the U4 project-first invitation lock order with one global installation/email/users/projects/invitations/memberships/credentials order and fixed the digest-only, key-rotatable, fragment-to-tokenless-POST link format plus service result contracts before implementation.
**Pages updated:** `docs/plans/2026-08-05-001-feat-self-hosted-source-release-plan.md`, wiki/decisions.md, wiki/log.d/20260805T225000Z-u4-admission-contract.md, wiki/log.md
**Source:** U4 architecture and correctness review against current auth, invitation, membership, and deployment code

## [2026-08-05] Harden admission identity and authentication-token persistence

**Action:** Added preflight-first canonical user/provider/invitation identity constraints, checked active/suspended accounts, durable cancelled invitation state, append-only installation audit events, and digest-only exact-purpose authentication-token rows with versioned key fingerprints and adapter-safe partial uniqueness.
**Pages updated:** wiki/data-model.md, wiki/schema-evolution.md, wiki/models/user.md, wiki/models/project-invitation.md, wiki/models/authentication-token.md, wiki/models/installation-audit-event.md, wiki/index.md, wiki/log.d/20260805T231500Z-u4-identity-token-foundation.md, wiki/log.md
**Source:** migrations `20260805132000` and `20260805133000`, shared identity/token models, SQLite upgrade tests, PostgreSQL 16 fresh/upgrade constraint tests

## [2026-08-06] Enforce the core and SaaS capability boundary

**Action:** Made the self-hosted core unlimited without subscription reads and removed hosted billing, Stripe, analytics, legal, upgrade, and support surfaces from that edition while preserving SaaS behavior from the same revision. Replaced the generic administrator alias with a configured SaaS-operator policy distinct from installation administration.
**Pages updated:** wiki/models/user.md, wiki/controllers/web-controllers.md, wiki/routes.md, wiki/log.d/20260806T001500Z-core-saas-capability-boundary.md, wiki/log.md
**Source:** `Screenote::Deployment` capability checks, user quota policy, conditional routes/rendering, and dual-edition route/query regressions

## [2026-08-06] Upload credentials leave request URLs

**Action:** Moved short-lived MCP screenshot upload credentials from query strings into `Authorization: Bearer`, returned URL/token/content type separately, and added URL-secrecy plus ID-enumeration regressions.

**Source:** `wiki/log.d/20260805T233549Z-upload-bearer-header.md`

## [2026-08-06] Add auditable self-hosted instance administration

**Action:** Added singleton-administrator account listing, suspension/restoration, comprehensive credential revocation, atomic authority transfer, issuer-bound single-use recovery, local operator recovery/transfer commands, and serialized credential issuance. Centralized browser identity replacement so successful password, OAuth, invitation, magic-link, recovery, registration, and bootstrap flows cannot leave another account's permanent session replayable.
**Pages updated:** wiki/instance-administration.md, wiki/models/authentication-token.md, wiki/data-model.md, wiki/controllers/web-controllers.md, wiki/self-hosting.md, wiki/index.md, wiki/log.d/20260806T003000Z-instance-administration.md, wiki/log.md
**Source:** `app/services/instance_accounts`, `app/services/account_recoveries`, `app/services/installations/transfer_administrator.rb`, instance/recovery controllers, session/OAuth issuance boundaries, operator tasks, migration `20260805134000`, and U5 security/concurrency/browser regressions

## [2026-08-06] Preflight complete publication and recovery boundaries

**Action:** Made publication refresh live GitGuardian incidents, classify every remote object before writing, and sign the retained source predicate under the separate authorizing workflow identity. Bound whole-instance backup and restored startup to the exact portable Compose secret file set rendered under a sanitized environment.
**Pages updated:** docs/releases.md, docs/self-hosting/backup-and-restore.md, wiki/self-hosting.md, wiki/log.d/20260806T031500Z-release-and-secret-contracts.md, wiki/log.md
**Source:** `.github/workflows/release.yml`, `.github/workflows/secrets.yml`, `lib/screenote/self_hosted/host_operations.rb`, release and operations contract regressions

## [2026-08-06] Harden browser authentication boundaries

**Action:** Made password login timing-safe across missing, suspended, and active identities; removed one-time recovery and invitation credentials before Turbo snapshot caching; made transient link-exchange failures explicitly retryable without persisting the raw credential; bound invitation OAuth callbacks to a current exact local intent marker; and connected OmniAuth's POST validator to Rails' actual encrypted-session CSRF token.
**Pages updated:** wiki/controllers/web-controllers.md, wiki/instance-administration.md, wiki/log.d/20260806T073437Z-authentication-boundary-hardening.md, wiki/log.md
**Source:** session, authentication-link, membership, instance-account, and OmniAuth controllers/views with focused controller and browser regressions
