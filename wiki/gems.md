---
title: Gem Choices
type: architecture
source: Gemfile
created: 2026-04-10
updated: 2026-04-10
tags: [gems, dependencies, rationale]
---

# Gem Choices

TLDR: Screenote uses a minimal, Rails-native gem set. Key choices: rails_simple_auth for auth, Doorkeeper for OAuth 2.1, Stripe for billing, fast-mcp for MCP server, Solid Queue/Cache/Cable for infrastructure (no Redis).

Source: `Gemfile`

## Core Framework

| Gem | Version | Rationale |
|-----|---------|-----------|
| `rails` | ~> 8.1.2 | Latest Rails with built-in Solid Queue/Cache/Cable support |
| `puma` | >= 5.0 | Default Rails web server |
| `propshaft` | - | Modern asset pipeline (replacement for Sprockets), no build step |
| `importmap-rails` | - | ESM import maps, no npm/webpack/esbuild needed |
| `turbo-rails` | - | Hotwire Turbo for SPA-like navigation |
| `stimulus-rails` | - | Hotwire Stimulus for JS controllers |

## Database

| Gem | Version | Rationale |
|-----|---------|-----------|
| `sqlite3` | >= 2.1 | Dev/test database (simple, zero-config) |
| `pg` | ~> 1.1 | Production database (PostgreSQL via Kamal) |

## Auth

| Gem | Version | Rationale |
|-----|---------|-----------|
| `bcrypt` | ~> 3.1.7 | Password hashing (has_secure_password) |
| `rails_simple_auth` | ~> 1.1.0 | Lightweight auth: email/password, magic links, email confirmation. Chosen over Devise for simplicity. |
| `omniauth` | - | OAuth consumer framework for social sign-in |
| `omniauth-google-oauth2` | - | Google sign-in |
| `omniauth-github` | - | GitHub sign-in |
| `doorkeeper` | - | OAuth 2.1 provider for MCP auth. Supports PKCE, dynamic client registration, project-scoped tokens. |

## Infrastructure (No Redis)

| Gem | Version | Rationale |
|-----|---------|-----------|
| `solid_cache` | - | Database-backed cache (replaces Redis for caching) |
| `solid_queue` | - | Database-backed job queue (replaces Sidekiq/Redis) |
| `solid_cable` | - | Database-backed Action Cable adapter |

## File Storage

| Gem | Version | Rationale |
|-----|---------|-----------|
| `image_processing` | ~> 1.2 | Image manipulation for annotation cropping (uses libvips) |
| `aws-sdk-s3` | - | S3-compatible storage client (Rabata S3) |

## External Services

| Gem | Version | Rationale |
|-----|---------|-----------|
| `stripe` | - | Payment processing for Pro subscriptions |
| `resend` | - | Transactional email delivery |
| `honeybadger` | - | Error monitoring and alerting |
| `fast-mcp` | - | MCP (Model Context Protocol) server for AI agent integration |

## Deployment

| Gem | Version | Rationale |
|-----|---------|-----------|
| `kamal` | - | Docker-based deployment (Kamal 2) |
| `thruster` | - | HTTP caching/compression proxy in front of Puma |
| `bootsnap` | - | Boot time optimization via caching |

## Development & Test

| Gem | Purpose |
|-----|---------|
| `debug` | Ruby debugger |
| `dotenv-rails` | Load .env in dev/test |
| `web-console` | In-browser console on error pages |
| `letter_opener` | Preview emails in browser (dev) |
| `rubocop-rails-omakase` | Rails-official linting config |
| `brakeman` | Security static analysis |
| `bundler-audit` | Gem vulnerability scanning |
| `capybara` | Browser testing framework |
| `capybara-playwright-driver` | Playwright driver for E2E tests |

## Notable Absences

- **No Devise** -- rails_simple_auth is lighter weight
- **No Redis** -- Solid Queue/Cache/Cable use the database instead
- **No Sidekiq** -- Solid Queue replaces it
- **No webpack/esbuild/vite** -- importmap-rails for zero-build JS
- **No Tailwind** -- vanilla CSS with BEM naming
- **No RSpec** -- MiniTest only (Rails default)
- **No jQuery** -- Stimulus controllers for all JS

See also: [[architecture]], [[decisions]]
