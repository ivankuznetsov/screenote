---
title: Architecture
type: architecture
source: CLAUDE.md, Gemfile, config/routes.rb, config/database.yml
created: 2026-04-10
updated: 2026-08-08
tags: [architecture, overview, stack, integrations]
---

# Architecture

TLDR: Screenote is a Rails 8.1 visual feedback tool for teams and coding agents. Users upload screenshots, annotate them with Figma-style comments, and agents retrieve annotations and image crops through the JSON CLI. Built with Hotwire (Turbo + Stimulus), no build step, and an Active Record database boundary. The supported self-hosted runtime uses SQLite; the hosted Kamal configuration currently selects PostgreSQL, but that is deployment topology rather than an application or release-qualification requirement. A legacy MCP runtime remains in source but is no longer the public integration path.

Source: `CLAUDE.md`, `Gemfile`, `config/routes.rb`, `config/database.yml`

## High-Level Architecture

```
Browser (Turbo + Stimulus)
    |
    v
Rails 8.1 (Puma + Thruster)
    |
    +-- Web UI (controllers + views, viewport switcher)
    +-- REST API (Api::V1 namespace, bearer auth)
    +-- Legacy MCP Server (fast-mcp gem, OAuth 2.1/API key auth)
    +-- Stripe Webhooks (hosted SaaS only)
    |
    +-- Active Storage (local/generic S3 self-hosted; Rabata hosted)
    +-- Active Record -> configured database URLs
        +-- SQLite (supported self-hosted runtime)
        +-- PostgreSQL (current hosted Kamal topology)
    +-- Solid Queue (background jobs)
    +-- Solid Cache (caching)
    +-- Solid Cable (WebSockets)
    +-- Doorkeeper (OAuth 2.1 provider)
    +-- Optional providers (SMTP, social OAuth, monitoring)
```

## Stack

| Layer | Technology |
|-------|-----------|
| Language | Ruby 3.4.10+ |
| Framework | Rails 8.1.2+ |
| Database | Active Record adapter-neutral application boundary; SQLite for the supported self-hosted runtime; PostgreSQL selected by the current hosted Kamal configuration |
| Frontend JS | Stimulus (import maps, no build step) |
| Frontend rendering | Turbo (Turbo Drive, Turbo Frames, Turbo Streams) |
| Assets | Propshaft |
| CSS | Vanilla CSS with BEM naming |
| Auth | rails_simple_auth; optional Google/GitHub OmniAuth |
| OAuth Provider | Doorkeeper (OAuth 2.1 with PKCE) |
| File Storage | Active Storage: local or generic S3-compatible self-hosting; Rabata for hosted SaaS |
| Background Jobs | Solid Queue |
| Caching | Solid Cache |
| WebSockets | Solid Cable |
| Payments | Stripe for hosted SaaS only |
| Email | Optional external SMTP for self-hosting; Resend for hosted SaaS |
| Monitoring | Optional Honeybadger for self-hosting; required for hosted SaaS |
| Deployment | Kamal 2 |
| HTTPS edge | Kamal Proxy; hosted DNS/CDN may also use Cloudflare |

## Core Workflows

### 1. Upload Screenshot (current)
User uploads image -> annotates in browser -> Agent collects via the CLI

### 2. Agent-Initiated Feedback Loop (killer feature)
Agent screenshots localhost -> uploads with the Screenote CLI -> Human annotates in browser -> Agent reads feedback with the CLI -> Agent fixes code -> repeat

### 3. Enter URL (future)
User enters URL -> server captures page -> User annotates -> Agent collects

## Key Patterns

- **Fat models, skinny controllers** -- business logic in models, controllers only do routing/auth
- **Service objects** for complex operations (only `AnnotationCropService` exists currently)
- **Concern-based auth** -- `ProjectAuthorization` concern shared across controllers needing project-level access checks
- **Dual auth systems** -- Web UI uses session-based auth (rails_simple_auth); the REST API and CLI use bearer tokens issued through OAuth 2.1 (Doorkeeper). The legacy MCP runtime accepts the same authorization boundary.
- **Enum-backed status fields** -- integer enums for annotation status, comment actions, subscription plan/status, project membership roles, invitation status, screenshot status
- **ScreenshotImage variants** -- a Screenshot is a logical capture/version and one or more ScreenshotImage rows own the actual viewport-specific blobs
- **Percentage-based coordinates** -- annotations use 0.0-100.0 percentage coordinates and are scoped to desktop/tablet/mobile viewports
- **Database portability boundary** -- models, services, tests, CI, and release qualification express database behavior through Active Record and role-specific URLs. Deployment configuration chooses the runtime adapter; exact-image SaaS qualification does not assert an adapter name or server version.

## External Integrations

| Service | Edition | Purpose | Config |
|---------|---------|---------|--------|
| Generic S3-compatible storage | Self-hosted, optional | Screenshot storage | `SCREENOTE_S3_*` env vars |
| External SMTP provider | Self-hosted, optional | Transactional email | `SCREENOTE_SMTP_ENABLED`, `SMTP_*` |
| Google/GitHub OAuth | Self-hosted optional; hosted required | Social sign-in | provider client ID/secret settings |
| Honeybadger | Self-hosted optional; hosted required | Error monitoring and alerting | `HONEYBADGER_API_KEY` |
| Stripe | Hosted SaaS | Subscription billing | `STRIPE_PRO_PRICE_ID`, `STRIPE_WEBHOOK_SECRET` |
| Rabata S3 | Hosted SaaS | Screenshot storage | `RABATA_*` env vars |
| Resend | Hosted SaaS | Transactional email | `RESEND_API_KEY` |
| Cloudflare | Hosted SaaS | DNS/CDN edge | DNS configuration |

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
  tools/              # legacy FastMCP tools plus ApplicationTool base
  javascript/
    controllers/      # Stimulus controllers
  assets/
    stylesheets/      # BEM CSS
  views/
    layouts/          # app, auth, landing layouts
```

See also: [[routes]], [[gems]], [[data-model]], [[decisions]], [[mcp-tools]]
