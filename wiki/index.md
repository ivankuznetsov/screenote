---
title: Wiki Index
type: architecture
source: wiki/
created: 2026-04-10
updated: 2026-04-11
tags: [index, catalog]
---

# screenote -- Wiki Index

*Auto-generated. Do not edit manually.*
*Last updated: 2026-04-11*

## Architecture

- [[architecture]] -- High-level app structure, patterns, external integrations
- [[data-model]] -- Entity relationship overview with Mermaid ER diagram
- [[schema-evolution]] -- Major schema changes and why
- [[routes]] -- Complete route surface area, namespaces, auth requirements
- [[gems]] -- Key gem choices with rationale
- [[decisions]] -- Architectural decisions from git history (12 ADRs)
- [[active-areas]] -- What's being actively worked on

## Planning

- [[plans-and-initiatives]] -- All active plans: product vision, Page/Version hierarchy, help page redesign, Claude Code skill
- [[roadmap]] -- What's planned, in progress, and recently done; high-level project direction
- [[technical-debt]] -- Code quality issues, deferred work, and security findings from 151 todos

## Models

- [[models/user]] -- Central identity model with auth concerns
- [[models/project]] -- Top-level container for pages and team collaboration
- [[models/page]] -- Groups screenshots within a project
- [[models/screenshot]] -- Uploaded image canvas for annotations
- [[models/annotation]] -- Feedback pinned to screenshot regions (point or rectangle)
- [[models/annotation-comment]] -- Threaded comments with action tracking
- [[models/api-key]] -- Project-scoped bearer tokens for API auth
- [[models/project-membership]] -- User-project join table with roles
- [[models/project-invitation]] -- Email-based project invitations
- [[models/subscription]] -- Stripe subscription state (free/pro)
- [[models/session]] -- Database-backed user sessions
- [[models/current]] -- Thread-local request context (CurrentAttributes)
- [[models/application-record]] -- Abstract base class

## Controllers

- [[controllers/web-controllers]] -- Web UI controllers (14 total: projects, pages, screenshots, annotations, invitations, billing, admin, static pages)
- [[controllers/api-controllers]] -- REST API controllers (bearer token auth, screenshot upload, annotation listing)
- [[controllers/oauth-controllers]] -- OAuth 2.1 provider (Doorkeeper authorization, dynamic client registration, metadata)

## Services

- [[services/annotation-crop-service]] -- Image cropping for annotation regions (used by MCP tools)

## Meta

- [[gaps]] -- What's missing or needs documentation
- [[log]] -- Append-only changelog of wiki operations
