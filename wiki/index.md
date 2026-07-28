---
title: screenote Wiki
type: index
source: wiki/**/*.md
created: 2026-05-14
updated: 2026-07-28
tags: [index, wiki]
---


**TLDR**: Catalog of the LLM-maintained wiki for `screenote`.

Page count: 40
Updated: 2026-07-28

## Core Architecture

- [[architecture]] — Rails 8.1 app architecture, integrations, and major patterns.
- [[data-model]] — Current schema, relationships, indexes, and FK behavior.
- [[schema-evolution]] — Migration timeline through Stripe hardening and multi-viewport screenshots.
- [[routes]] — Web, REST API, OAuth, viewport, webhook, and static routes.
- [[decisions]] — Lightweight ADRs from git history.
- [[dependencies]] — Dependency files and stack notes.
- [[gems]] — Gem choices and rationale.
- [[commands]] — Controller/command source inventory.
- [[mcp-tools]] — FastMCP transport/auth behavior and current tool inventory.
- [[api-cli]] — Go REST CLI commands, configuration, JSON/error contract, and deferred surface area.

## Controllers And Services

- [[controllers/web-controllers]] — Browser UI controllers and public static pages.
- [[controllers/api-controllers]] — REST and signed-upload API controllers.
- [[controllers/oauth-controllers]] — Doorkeeper, DCR, and OAuth metadata controllers.
- [[services/annotation-crop-service]] — Cropped annotation image generation.
- [[frontend-review-ui]] — Project-card navigation, guarded overview thumbnails, sticky annotation workflow, viewport centering, and pin geometry.

## Models

- [[models/application-record]] — ApplicationRecord base model.
- [[models/current]] — Request-local current state.
- [[models/session]] — Database-backed sessions.
- [[models/user]] — Authenticated users.
- [[models/project]] — Project ownership and memberships.
- [[models/page]] — Logical pages/screens under projects.
- [[models/snapshot]] — Capture-run records grouping screenshots by commit and timestamp.
- [[models/screenshot]] — Logical capture/version records.
- [[models/screenshot-image]] — Per-viewport image variants, overview thumbnail warming, and request-safe delivery.
- [[models/annotation]] — Viewport-scoped visual feedback.
- [[models/annotation-comment]] — Threaded comments and resolution audit log.
- [[models/api-key]] — Project-scoped bearer tokens.
- [[models/project-membership]] — Project membership roles.
- [[models/project-invitation]] — Email invitations.
- [[models/subscription]] — Stripe subscription state.
- [[models/stripe-webhook-event]] — Stripe webhook idempotency ledger.

## Planning And Operations

- [[active-areas]] — Recently active development areas from git history.
- [[plans-and-initiatives]] — Active plans and implemented plan status.
- [[roadmap]] — Current product/engineering priorities.
- [[technical-debt]] — Todo-derived debt, cross-checked against source drift.
- [[testing-and-ci]] — Minitest, Capybara/Playwright, responsive-image proof, overview performance contracts, and local CI commands.
- [[gaps]] — Missing coverage and uncertainty.
- [[index]] — This catalog.
- [[log]] — Append-only wiki changelog.

## Maintenance

- Managed config: `.llm-wiki/config.json`
- Headless refresh: `.llm-wiki/refresh-wiki.sh`
- Post-commit refresh: `.llm-wiki/post-commit-refresh.sh`
- [[llm-wiki-maintenance]] — Managed wiki refresh scripts, log fragments, worktree-safe post-commit behavior, and cross-project wiki lookup notes.
