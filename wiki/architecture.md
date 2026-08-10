---
title: Architecture
type: architecture
source: CLAUDE.md, Gemfile, Dockerfile, bin/docker-entrypoint, app/jobs/reconcile_screenshot_processing_job.rb, config/routes.rb, config/database.yml, config/deploy.saas.yml
created: 2026-04-10
updated: 2026-08-10
tags: [architecture, overview, stack, integrations, deployment, once, kamal-saas]
---

# Architecture

TLDR: Screenote is a Rails 8.1 visual feedback tool for teams and coding agents. Users upload screenshots, annotate them with Figma-style comments, and agents retrieve annotations and image crops through the JSON CLI. Built with Hotwire (Turbo + Stimulus), no build step, and an Active Record database boundary. Public self-hosting runs the `latest` release channel through ONCE as one container, four SQLite databases, and one durable volume; hosted `screenote.ai` keeps its separate Kamal topology. A legacy MCP runtime remains in source but is no longer the public integration path.

Source: `CLAUDE.md`, `Gemfile`, `Dockerfile`, `bin/docker-entrypoint`,
`app/jobs/reconcile_screenshot_processing_job.rb`, `config/routes.rb`,
`config/database.yml`, `config/deploy.saas.yml`

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
| Deployment | ONCE stable channel for public self-hosting; Kamal 2 for hosted `screenote.ai` |
| HTTPS edge | ONCE's Kamal Proxy for self-hosting; hosted Kamal Proxy and DNS/CDN may also use Cloudflare |

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
- **Edition-specific deployment boundary** -- the published image defaults to the self-hosted edition and is deployed from the `latest` release channel with released stock ONCE and automatic updates enabled. Operators install ONCE with `curl https://get.once.com | ONCE_INTERACTIVE=false sh`, then pass `once deploy` an explicit host and matching `SCREENOTE_BASE_URL`. The first visitor atomically claims the administrator; no setup credential is configured. The container serves port 80, trusts only the Thruster loopback peer, promotes the forwarded client only when the final hop matches the current ONCE proxy identity from a bounded, short-lived DNS snapshot, and stores all four SQLite roles plus local Active Storage data on one volume mounted at `/storage` and `/rails/storage`. A direct sibling or failed identity refresh is attributed to its own final address instead of its supplied prefix. Hosted SaaS uses the same named-proxy normalization and deploys separately with Kamal.
- **Non-blocking startup recovery** -- the entrypoint prepares the databases and installation, then requires Solid Queue to accept a reconciliation job before Puma starts. Processing recovery runs asynchronously and repeats every five minutes rather than delaying the listening server for the whole image corpus.

## External Integrations

| Service | Edition | Purpose | Config |
|---------|---------|---------|--------|
| Generic S3-compatible storage | Self-hosted, optional | Screenshot storage | `SCREENOTE_S3_*` env vars |
| External SMTP provider | Self-hosted, optional | Transactional email | ONCE Email settings (`SMTP_*`, `MAILER_FROM_ADDRESS`); optional `SCREENOTE_SMTP_ENABLED` override |
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
