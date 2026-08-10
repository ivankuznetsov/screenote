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
**Status**: Superseded by ADR-019; superseded the 2026-08-07 public Kamal deployment decision
**Context**: The first public deployment design required a repository fork, an exact source checkout, a tracked self-hosted Kamal configuration, local Ruby tooling, and a custom release-aware Kamal wrapper. That made installing one qualified container substantially harder than the product topology required. ONCE can manage a custom Docker image, TLS proxying, a persistent volume, environment, updates, and backups directly on the application host.
**Decision**: Public self-hosting moved from Kamal to ONCE and the GHCR release image, initially through a proposed Screenote-specific upstream installer that would provide host/TLS configuration automatically. It also established the first-visitor claim, automatic-update, persistent-volume, proxy, backup/restore, optional-provider, and hosted-Kamal boundaries retained by ADR-019.
**Rationale**: The runtime fits ONCE's single-container contract and does not justify a repository fork or public Kamal configuration. The proposed upstream integration would have made setup short, but it was not part of a released stock ONCE contract, so ADR-019 replaces that dependency with explicit application configuration.

## ADR-019: Released Stock ONCE with Explicit Canonical URL

**Date**: 2026-08-10
**Status**: Active; supersedes ADR-018's Screenote-specific installer contract
**Context**: The simplest public flow must work with released stock ONCE. Depending on an unreleased upstream Screenote integration would block publication and make the documented install differ from software operators can actually obtain.
**Decision (user-directed)**: Operators install released stock ONCE with `curl https://get.once.com | ONCE_INTERACTIVE=false sh`, then deploy `ghcr.io/ivankuznetsov/screenote:latest` with `--host screenote.example.com` and `--env SCREENOTE_BASE_URL=https://screenote.example.com`. HTTP-only and S3 first deployments must also provide an explicit base URL whose scheme and hostname match ONCE. No administrator setup credential or update-disable flag is part of the flow: the first visitor atomically claims the administrator, automatic application updates remain enabled, and bare `once update HOST` requests an immediate update. Public self-hosting still uses ONCE's proxy, one durable volume, generic SMTP integration, backup/restore commands, and separate external S3 recovery; Kamal remains internal to hosted `screenote.ai`.
**Rationale**: Stock ONCE plus one explicit canonical URL is available now, keeps the operator contract auditable, and avoids coupling Screenote's release to upstream catalog or environment-injection changes. The explicit origin remains static and independent of caller-controlled request headers. Exact-image deployment, proxy, update, backup, and restore drills continue to gate publication.

See also: [[architecture]], [[schema-evolution]], [[active-areas]], [[models/screenshot-image]]
