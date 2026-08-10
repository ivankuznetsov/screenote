---
title: Architectural Decisions
type: decision
source: git log, Dockerfile, bin/docker-entrypoint, app/jobs/reconcile_screenshot_processing_job.rb, lib/screenote/deployment.rb, docs/once-deployment.md, config/deploy.saas.yml
created: 2026-04-10
updated: 2026-08-10
tags: [decisions, adr, architecture, history, deployment, once]
---

# Architectural Decisions

TLDR: Key decisions extracted from history and current source as lightweight ADRs. Screenote evolved through foundation, agent integration, collaboration, annotation threading, release hardening, database portability, and a split deployment model: ONCE for public self-hosting and Kamal only for hosted `screenote.ai`.

Source: `git log --all --oneline` (112 commits total)

## ADR-001: Rails 8 with No-Build Frontend

**Date**: 2026-02-11 (commit `33d1709`)
**Status**: Active
**Context**: Needed a web framework for a visual feedback SaaS.
**Decision**: Rails 8.1 with importmap-rails (no npm build step), Propshaft, Stimulus + Turbo.
**Rationale**: Minimal complexity, no Node.js dependency, fast iteration. The app is server-rendered with Hotwire for interactivity.

## ADR-002: SQLite Dev / PostgreSQL Prod

**Date**: 2026-02-11 (commit `33d1709`)
**Status**: Superseded by ADR-017
**Context**: Need a database strategy for development vs production.
**Decision**: SQLite for development and test, PostgreSQL for production.
**Rationale**: SQLite is zero-config for local dev. PostgreSQL handles production concurrency and is required for some features.

## ADR-003: Solid Queue/Cache/Cable (No Redis)

**Date**: 2026-02-11 (commit `33d1709`)
**Status**: Active
**Context**: Background jobs, caching, and WebSocket infrastructure.
**Decision**: Use Rails 8 Solid Queue, Solid Cache, and Solid Cable instead of Redis.
**Rationale**: Eliminates Redis as an infrastructure dependency. Database-backed adapters are sufficient for Screenote's scale.

## ADR-004: MCP Server with API Key Auth

**Date**: 2026-02-11 (commit `4599a19`)
**Status**: Superseded by ADR-007 (OAuth added, API keys still supported for REST API)
**Context**: AI agents need to read annotations and upload screenshots.
**Decision**: fast-mcp gem with bearer token API keys per project.
**Rationale**: Simple, project-scoped access. API keys are hashed with SHA-256, never stored in plaintext.

## ADR-005: Percentage-Based Annotation Coordinates

**Date**: 2026-02-11 (commit `1f2a97b`)
**Status**: Active
**Context**: Annotations need to work at any display resolution.
**Decision**: Store x/y/width/height as percentages (0.0-100.0) rather than pixel values.
**Rationale**: Resolution-independent. Works across different screen sizes without recalculation.

## ADR-006: Project Collaboration via Email Invitations

**Date**: 2026-02-12 (commit `effed89`)
**Status**: Active
**Context**: Multiple users need to collaborate on the same project.
**Decision**: ProjectMembership (owner/member roles) + ProjectInvitation (email-based, 7-day token expiry).
**Rationale**: Simple role model. Invitations work for users who don't have accounts yet.

## ADR-007: OAuth 2.1 with PKCE for MCP

**Date**: 2026-02-16 (commit `0c69e90`)
**Status**: Active
**Context**: MCP clients (like Claude Desktop) need standardized auth, not custom API keys.
**Decision**: Add Doorkeeper as OAuth 2.1 provider with PKCE support, dynamic client registration (RFC 7591), and standard metadata endpoints (RFC 8414, RFC 9728).
**Rationale**: MCP specification requires OAuth 2.1. Dynamic registration lets any MCP client connect without manual setup. Tokens are scoped to projects.

## ADR-008: Stripe for Billing (Free/Pro Tiers)

**Date**: 2026-02-14 (commit `4f52489`)
**Status**: Active
**Context**: Need a monetization model.
**Decision**: Free tier (1 project, 1 team member) and Pro tier ($10/month, unlimited). Stripe Checkout + Billing Portal. Webhook-driven state sync.
**Rationale**: Stripe handles payment complexity. Webhook-driven ensures state stays in sync even if user closes browser during checkout.

## ADR-009: Page Hierarchy (Project -> Page -> Screenshot)

**Date**: 2026-02-20 (commit `dea90b0`)
**Status**: Active
**Context**: Screenshots were flat under projects, making organization difficult for large projects.
**Decision**: Add Page model between Project and Screenshot. Pages group screenshots (e.g., by URL or feature area). API auto-creates pages by name.
**Rationale**: Better organization without breaking existing API. `Page.find_or_create_by_name!` handles race conditions with case-insensitive matching.

## ADR-010: Annotation Comment Threads

**Date**: 2026-02-20 (commit `f59b764`)
**Status**: Active
**Context**: Need resolve/reopen workflow with audit trail for annotations.
**Decision**: Separate AnnotationComment model with action enum (comment/resolved/reopened). Resolve and reopen are transactional operations that update annotation status and create a comment atomically.
**Rationale**: Full audit trail of who resolved/reopened and when. Comments can come from users or API keys (agents).

## ADR-011: Single-use Bearer Upload for MCP

**Date**: 2026-02-16 (commit `f53042b`)
**Status**: Active
**Context**: MCP tools need to upload screenshot binary data, but MCP transport has size limits.
**Decision**: Two-step upload: (1) MCP creates a screenshot record and receives a credential-free upload URL plus a separate token, (2) the agent PUTs binary data with `Authorization: Bearer <token>` and the declared `Content-Type`.
**Rationale**: Avoids base64-encoding large images through MCP while keeping the five-minute single-use credential out of proxy logs, browser history, request paths, and query strings.

## ADR-012: Hourly Digest Notifications

**Date**: 2026-03-10 (commit `9f50825`)
**Status**: Active
**Context**: Need to notify annotation authors when their annotations are resolved.
**Decision**: Hourly digest emails collecting all unnotified resolved annotation comments. Track notification state via `notified_at` on annotation_comments.
**Rationale**: Avoids email spam from rapid resolve/unresolve cycles. Per-author tracking prevents duplicate emails on retry.

## ADR-013: Stripe Webhook Idempotency and Model-Owned State Transitions

**Date**: 2026-04-21 (commit `cd99da2`)
**Status**: Active
**Context**: Stripe webhook retries and API shape changes created risk of duplicate side effects and stale subscription state.
**Decision**: Add `StripeWebhookEvent` as an idempotency ledger, move subscription state transitions onto `Subscription`, use row locks around webhook mutations, and read `current_period_end` from the subscription item for Stripe API 2026-01-28.
**Rationale**: Unique event ids make retries safe, model methods concentrate state transition rules, and row locks reduce TOCTOU risk.

## ADR-014: ScreenshotImage Child Model for Multi-Viewport Captures

**Date**: 2026-04-21 (commits `7f413b2`, `9786e6e`, `85d22c3`)
**Status**: Active
**Context**: Responsive review needs desktop/tablet/mobile images under one logical capture without splitting feedback into unrelated screenshots.
**Decision**: Add `ScreenshotImage` child rows with per-viewport blobs, dimensions, status, and upload tokens. Add `Annotation#viewport` and a viewport switcher route `/screenshots/:id/viewports/:viewport`.
**Rationale**: Per-variant rows make upload tokens, analysis status, retry, and UI filtering explicit. Annotations remain percentage-based but are scoped to the layout they reference.

## ADR-015: Explicit Authenticated Principals and Server-Owned OAuth Consent

**Date**: 2026-08-05
**Status**: Active
**Context**: REST and MCP had separate identity fields, API keys impersonated project creators, nullable OAuth project IDs could widen authority, and read/write scope behavior drifted by transport.
**Decision**: Use one immutable `AuthenticatedPrincipal` across REST and MCP. OAuth grants are user-scoped by default or project-scoped only after a signed-in user selects a current membership on Screenote's consent screen. Persist that binding through code/device exchange and refresh; reject membership loss and cascade project deletion. Serialize project consent, code/device exchange, refresh, and member removal in user -> project -> membership -> credential order, retaining authority locks through credential creation. API-key content records the key as actor while retaining a separate immutable issuer. Register only an explicit MCP allowlist with exact scopes and safety metadata.
**Rationale**: Authority is server-derived, auditable, and transport-independent. Transactional serialization closes membership-loss TOCTOU windows and preserves at least one owner under concurrent removals on both PostgreSQL and SQLite. A deleted project, removed member, revoked key, or future tool subclass cannot silently widen remote access.

## ADR-016: Digest-Only Authentication Links and Global Admission Locking

**Date**: 2026-08-05
**Status**: Superseded in part by ADR-017 for database locking and retry implementation
**Context**: Invitation and Rails authentication links currently place signed bearer values in URL paths and can create users through multiple controllers. The first U4 draft also ordered invitation locks project-first, opposite the user-first authority order established by OAuth and membership removal.
**Decision**: Persist purpose/subject-bound `AuthenticationToken` rows containing only a digest plus public derivation metadata. Reproduce 32-byte credentials through a versioned domain-separated HMAC keyring, carry them in URL fragments or equivalent Base32 manual codes, and exchange them by filtered POST into a tokenless session context. Missing historical derivation keys fail closed. All account and authority transitions lock in this order: Installation when relevant, normalized-email admission lock, users by ascending ID, projects by ascending ID, invitations by ascending ID, memberships, then tokens/credentials. PostgreSQL uses a transaction advisory lock for normalized email; production SQLite uses its immediate outer write transaction. Only outermost domain services perform bounded database retries. An invitation may create credentials for a new address, but an existing local account must authenticate through the ordinary rate-limited session flow before its matching signed-in identity can accept; the invitation endpoint never verifies an existing password.
**Rationale**: Database or job-queue access alone cannot reveal live link credentials; routine key rotation remains operable without silently retaining removed keys; no raw credential enters a request URL, referrer, session, or job argument; invitation links cannot become reusable password oracles; and invitation acceptance cannot deadlock against suspension, ownership loss, or membership removal by acquiring the same authority rows in reverse order.

## ADR-017: Active Record Database Portability Boundary

**Date**: 2026-08-08
**Status**: Active
**Context**: The original development/production split grew into adapter-specific application locks, retry classification, migration SQL, CI lanes, and PostgreSQL 16 assertions in exact-image SaaS qualification. Those checks coupled the application contract to one hosted deployment choice even though Active Record already exposes the required database roles and concurrency errors.
**Decision**: Keep application code, tests, required CI, migrations where adapter capabilities permit, and release qualification database-adapter-neutral through Active Record. Admission and authority serialization use durable rows and Active Record operations; retry policy consumes Active Record concurrency exceptions plus the supported SQLite cause chain without branching on adapter identity. Exact-image SaaS qualification remains mandatory on AMD64 and ARM64, but supplies primary, cache, queue, and cable as four URLs and verifies them without asserting an adapter name or server version. Runtime deployment remains edition-specific: supported self-hosting uses SQLite, while the current hosted Kamal configuration may provision PostgreSQL. Because the initial supported release has predecessor `none` and the hosted database is already current, one pre-v1 rebaseline removes PostgreSQL-only lock SQL from migrations `20260712153000`, `20260805130000`, `20260805131000`, and `20260805132000`; migration history is append-only from `v1.0.0` onward. The stopped-process credential cutover lets each migration use the transaction behavior supported by its adapter instead of wrapping the whole chain in one outer transaction. Its safety boundary is quiesced maintenance, a verified backup/restore point, migration-version-aware idempotent resume, and post-migration storage/runtime verification.
**Rationale**: Application correctness and release evidence should survive a database-provider change without losing exact-image SaaS coverage. Separating the application boundary from deployment topology keeps PostgreSQL available to the hosted service and SQLite appropriate for self-hosting, while avoiding a false promise that an interrupted multi-migration cutover can always be rolled back atomically.

## ADR-018: ONCE for Public Self-Hosting, Kamal for Hosted SaaS

**Date**: 2026-08-09
**Status**: Active; supersedes the 2026-08-07 public Kamal deployment decision
**Context**: The first public deployment design required a repository fork, an exact source checkout, a tracked self-hosted Kamal configuration, local Ruby tooling, and a custom release-aware Kamal wrapper. That made installing one qualified container substantially harder than the product topology required. ONCE can manage a custom Docker image, TLS proxying, a persistent volume, environment, updates, and backups directly on the application host.
**Decision**: Public self-hosting deploys the GHCR `latest` release channel through Screenote's native ONCE installer, exposed as exactly `curl https://get.once.com/screenote | sh`. ONCE prompts for the hostname, enables automatic application updates, and supplies `ONCE_HOST`, `DISABLE_SSL` when applicable, and `SECRET_KEY_BASE`. Screenote derives its canonical origin from the host/TLS settings; an explicit `SCREENOTE_BASE_URL` is an advanced override that must match when both are present. A fresh instance has no setup secret: the first visitor claims its administrator through a locked transactional single-winner transition, after which admission is invitation-only. Operators can request an immediate update with `once update HOST`; release promotion moves `latest` only after the exact candidate has passed qualification and its immutable GitHub Release exists. The image defaults to `SCREENOTE_EDITION=self_hosted`, forwards authoritative proxy headers through Thruster, and trusts loopback plus ONCE's verified proxy identity. ONCE mounts its one durable volume at both `/storage` and `/rails/storage` and interoperates with Screenote's generic SMTP configuration. Screenote enqueues startup image reconciliation before serving instead of performing the full corpus repair inline. A concurrency-discarded duplicate is accepted because an existing reconciliation already owns the work, while genuine queue errors still stop startup. ONCE pauses the container to copy local volume state during backup; an external S3 namespace remains a separate operator/provider recovery responsibility. Public self-hosting has no fork, source checkout, `config/deploy.yml`, or custom `bin/kamal` wrapper. Kamal and `config/deploy.saas.yml` remain internal to hosted `screenote.ai`.
**Rationale**: The runtime already fits ONCE's single-container contract, so one hostname prompt and one published image are simpler than asking operators to generate first-boot secrets or maintain deployment configuration. Native host/TLS injection preserves a static canonical origin without trusting request headers. The first-visitor claim accepts the familiar single-server setup tradeoff while database serialization prevents two administrators from winning concurrently. ONCE's default automatic updates minimize routine operation, while the bare update command remains available for immediate rollout. Release qualification and evidence stay bound to the immutable digest behind the moving public channel. Keeping hosted Kamal isolated preserves SaaS provider and database choices. The first release remains blocked until retained evidence proves ONCE deploy, restart, update, backup, and restore behavior, including separate S3 recovery where selected.

See also: [[architecture]], [[schema-evolution]], [[active-areas]], [[models/screenshot-image]]
