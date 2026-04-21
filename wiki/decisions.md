---
title: Architectural Decisions
type: decision
source: git log
created: 2026-04-10
updated: 2026-04-10
tags: [decisions, adr, architecture, history]
---

# Architectural Decisions

TLDR: Key decisions extracted from the git history as lightweight ADRs. Screenote evolved through 4 phases: foundation, MCP integration, collaboration, and annotation threading.

Source: `git log --all --oneline` (109 commits total)

## ADR-001: Rails 8 with No-Build Frontend

**Date**: 2026-02-11 (commit `33d1709`)
**Status**: Active
**Context**: Needed a web framework for a visual feedback SaaS.
**Decision**: Rails 8.1 with importmap-rails (no npm build step), Propshaft, Stimulus + Turbo.
**Rationale**: Minimal complexity, no Node.js dependency, fast iteration. The app is server-rendered with Hotwire for interactivity.

## ADR-002: SQLite Dev / PostgreSQL Prod

**Date**: 2026-02-11 (commit `33d1709`)
**Status**: Active
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

## ADR-011: Signed URL Upload for MCP

**Date**: 2026-02-16 (commit `f53042b`)
**Status**: Active
**Context**: MCP tools need to upload screenshot binary data, but MCP transport has size limits.
**Decision**: Two-step upload: (1) MCP creates screenshot record and gets a signed upload URL + token, (2) agent PUTs binary data directly to the upload endpoint.
**Rationale**: Avoids base64-encoding large images through the MCP transport. Upload tokens expire in 5 minutes and are single-use.

## ADR-012: Hourly Digest Notifications

**Date**: 2026-03-10 (commit `9f50825`)
**Status**: Active
**Context**: Need to notify annotation authors when their annotations are resolved.
**Decision**: Hourly digest emails collecting all unnotified resolved annotation comments. Track notification state via `notified_at` on annotation_comments.
**Rationale**: Avoids email spam from rapid resolve/unresolve cycles. Per-author tracking prevents duplicate emails on retry.

See also: [[architecture]], [[schema-evolution]], [[active-areas]]
