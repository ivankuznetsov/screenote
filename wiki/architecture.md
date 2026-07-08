---
title: Architecture
type: architecture
source: CLAUDE.md, Gemfile, config/routes.rb
created: 2026-04-10
updated: 2026-05-14
tags: [architecture, overview, stack, integrations]
---

# Architecture

TLDR: Screenote is a Rails 8.1 SaaS visual feedback tool for AI agents. Users upload screenshots, annotate them with Figma-style comments, and AI agents retrieve annotations (with cropped image regions) via MCP. Built with Hotwire (Turbo + Stimulus), no build step, SQLite in dev, PostgreSQL in production.

Source: `CLAUDE.md`, `Gemfile`, `config/routes.rb`

## High-Level Architecture

```
Browser (Turbo + Stimulus)
    |
    v
Rails 8.1 (Puma + Thruster)
    |
    +-- Web UI (controllers + views, viewport switcher)
    +-- REST API (Api::V1 namespace, bearer auth)
    +-- MCP Server (fast-mcp gem, OAuth 2.1/API key auth)
    +-- Stripe Webhooks
    |
    +-- Active Storage (Rabata S3)
    +-- Solid Queue (background jobs)
    +-- Solid Cache (caching)
    +-- Solid Cable (WebSockets)
    +-- Doorkeeper (OAuth 2.1 provider)
    +-- Honeybadger (error monitoring)
```

## Stack

| Layer | Technology |
|-------|-----------|
| Language | Ruby 3.4.7+ |
| Framework | Rails 8.1.2+ |
| Database (dev/test) | SQLite |
| Database (production) | PostgreSQL |
| Frontend JS | Stimulus (import maps, no build step) |
| Frontend rendering | Turbo (Turbo Drive, Turbo Frames, Turbo Streams) |
| Assets | Propshaft |
| CSS | Vanilla CSS with BEM naming |
| Auth | rails_simple_auth + OmniAuth (Google, GitHub) |
| OAuth Provider | Doorkeeper (OAuth 2.1 with PKCE) |
| File Storage | Active Storage with Rabata S3 |
| Background Jobs | Solid Queue |
| Caching | Solid Cache |
| WebSockets | Solid Cable |
| Payments | Stripe |
| Email | Resend |
| Monitoring | Honeybadger |
| Deployment | Kamal 2 |
| CDN/SSL | Cloudflare |

## Core Workflows

### 1. Upload Screenshot (current)
User uploads image -> annotates in browser -> Agent collects via MCP

### 2. Agent-Initiated Feedback Loop (killer feature)
Agent screenshots localhost -> uploads to Screenote via API -> Human annotates in browser -> Agent reads feedback via MCP -> Agent fixes code -> repeat

### 3. Enter URL (future)
User enters URL -> server captures page -> User annotates -> Agent collects

## Key Patterns

- **Fat models, skinny controllers** -- business logic in models, controllers only do routing/auth
- **Service objects** for complex operations (only `AnnotationCropService` exists currently)
- **Concern-based auth** -- `ProjectAuthorization` concern shared across controllers needing project-level access checks
- **Dual auth systems** -- Web UI uses session-based auth (rails_simple_auth), API uses bearer token auth (ApiKey), MCP uses OAuth 2.1 (Doorkeeper)
- **Enum-backed status fields** -- integer enums for annotation status, comment actions, subscription plan/status, project membership roles, invitation status, screenshot status
- **ScreenshotImage variants** -- a Screenshot is a logical capture/version and one or more ScreenshotImage rows own the actual viewport-specific blobs
- **Percentage-based coordinates** -- annotations use 0.0-100.0 percentage coordinates and are scoped to desktop/tablet/mobile viewports

## External Integrations

| Service | Purpose | Config |
|---------|---------|--------|
| Stripe | Subscription billing (Pro plan at $10/mo) | `STRIPE_PRO_PRICE_ID`, `STRIPE_WEBHOOK_SECRET` |
| Rabata S3 | File storage (screenshots) | `RABATA_*` env vars |
| Resend | Transactional email delivery | `RESEND_API_KEY` |
| Honeybadger | Error monitoring and alerting | `HONEYBADGER_API_KEY` |
| Google OAuth | Sign-in with Google | `GOOGLE_CLIENT_ID/SECRET` |
| GitHub OAuth | Sign-in with GitHub | `GITHUB_CLIENT_ID/SECRET` |
| Cloudflare | CDN, SSL termination | DNS config |

## Directory Structure

```
app/
  controllers/
    admin/            # Admin dashboard
    api/              # REST API (base + v1 namespace)
    oauth/            # OAuth authorization + registration
    concerns/         # Shared controller concerns
  models/             # core models, including ScreenshotImage viewport variants
  services/           # 1 service (AnnotationCropService)
  tools/              # 17 registered FastMCP tools plus ApplicationTool base
  javascript/
    controllers/      # Stimulus controllers
  assets/
    stylesheets/      # BEM CSS
  views/
    layouts/          # app, auth, landing layouts
```

See also: [[routes]], [[gems]], [[data-model]], [[decisions]], [[mcp-tools]]
