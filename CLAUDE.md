# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

Screenote is a SaaS visual feedback tool for AI agents. Users upload screenshots, annotate them with Figma-style comments, and AI agents retrieve those annotations (with the actual cropped image region) via MCP.

### Core Concepts

- **Screenshot** — an uploaded image that serves as the canvas for feedback
- **Annotation** — a comment pinned to a point or rectangular region of a screenshot (percentage-based coordinates + text)
- **MCP Server** — HTTP endpoint that AI agents connect to for reading annotations with visual context
- **Project** — groups screenshots, scoped by API key for MCP access

### Three Core Workflows

1. **Upload Screenshot**: User uploads image -> annotates in browser -> Agent collects via MCP
2. **Enter URL** (future): User enters URL -> server captures page -> User annotates -> Agent collects
3. **Agent-initiated** (killer feature): Agent screenshots localhost -> uploads to Screenote -> Human annotates -> Agent reads feedback -> Agent fixes -> repeat

### Authentication

Uses `rails_simple_auth` gem with:
- Email/password authentication
- Magic link (passwordless) sign-in
- Google and GitHub OAuth (via OmniAuth)
- Email confirmation
- Separate `auth` layout for auth pages (avoids Rails Engine namespace issues)

### Key Files

- `config/initializers/rails_simple_auth.rb` — auth configuration
- `config/initializers/omniauth.rb` — OAuth providers
- `app/models/user.rb` — includes Authenticatable, Confirmable, MagicLinkable, OAuthConnectable
- `app/models/session.rb` — database-backed sessions with expiry
- `app/models/current.rb` — delegates to RailsSimpleAuth::Current

## Build and Development Commands

```bash
# Install dependencies
bundle install

# Database setup
bin/rails db:create db:migrate db:seed

# Start development server (port 3005)
bin/dev

# Run all tests
bin/rails test

# Run a single test file
bin/rails test test/models/user_test.rb

# Run a specific test by line number
bin/rails test test/models/user_test.rb:42

# Run linter
bin/rubocop

# Auto-fix lint issues
bin/rubocop -a

# Security scan
brakeman -q
```

## Test Credentials

Development seed user: `test@screenote.app` / `password`

## Environment Variables

```bash
# Auth
MAILER_FROM=noreply@screenote.app
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GITHUB_CLIENT_ID=...
GITHUB_CLIENT_SECRET=...

# Storage (Rabata S3) — production only
RABATA_ACCESS_KEY_ID=...
RABATA_SECRET_ACCESS_KEY=...
RABATA_BUCKET=screenote-production
RABATA_REGION=eu-central-1
RABATA_ENDPOINT=https://s3.rabata.io

# Database (production only)
DATABASE_URL=postgresql://...
CACHE_DATABASE_URL=postgresql://...
QUEUE_DATABASE_URL=postgresql://...
CABLE_DATABASE_URL=postgresql://...

# Monitoring
HONEYBADGER_API_KEY=...
HONEYBADGER_JS_API_KEY=...
```

## Rails Development Rules

### Philosophy
Write code that would make DHH proud and pass code review at 37signals. Always choose the Rails way:
- Convention over configuration
- Don't repeat yourself (DRY)
- Fat models, skinny controllers
- RESTful resources with standard CRUD actions
- Prefer Rails built-ins over gems when possible
- Simple, readable code over clever abstractions

### Stack
- Ruby 3.4.7+
- Rails 8.1.2+
- SQLite (development/test), PostgreSQL (production)
- Kamal for deployment

### Pre-commit Checklist
Run before each commit:
```bash
bin/rubocop              # Linting
brakeman -q              # Security scan
bin/rails test           # All tests pass
```

### Key Conventions
- **MiniTest only** — no RSpec, use fixtures for test data
- **BEM CSS naming** — `.block`, `.block__element`, `.block--modifier`
- **Thin controllers** — business logic in models or service objects
- **No jQuery** — Stimulus controllers for all JS interactions
- **No inline styles** — all CSS in `app/assets/stylesheets/`
- **No JS alerts** — use proper UI notifications
- **No-build approach** — importmap for JS, Propshaft for assets, no npm build step
- **Integer-backed enums** for all status fields
- **Percentage-based coordinates** (0.0-100.0) for annotations

### Development Patterns
- **Turbo Streams** for real-time updates
- **Stimulus controllers** for JavaScript behavior
- **Solid Queue** for background jobs
- **Solid Cache** for caching (database-backed, no Redis)
- **Service objects** (`app/services/`) for complex operations — instance-based with class convenience methods
- Use native Turbo logic instead of custom JavaScript wherever possible
- Proper error handling with user-friendly messages — never show detailed errors to users
- Send all errors to Honeybadger for monitoring
- Never store images in database — use Rabata S3 for file storage

### Deployment (Kamal)
```bash
kamal deploy             # Deploy to production
kamal console            # Production Rails console
kamal logs -f            # View production logs
kamal shell              # Bash shell on server
```

<!-- BEGIN LLM WIKI -->
## LLM Wiki

This project has a managed LLM wiki. Treat it as required project context.

- Project wiki: `wiki/`
- Index: `wiki/index.md`
- Change log: `wiki/log.md` compiled from `wiki/log.d/*.md`
- Known gaps: `wiki/gaps.md`
- Raw notes: `raw/notes/`

Before planning, implementation, review, or debugging:

1. Read `wiki/index.md`.
2. Search the project wiki with `qmd search "<topic>"` when QMD is available, or `rg "<topic>" wiki/` otherwise.
3. Use `qmd query "<topic>"` only when local model generation is acceptable; if it hangs or errors, fall back to `qmd search` or `rg`.
4. If `.llm-wiki/config.json` has `main_wiki_path`, search that main wiki too.
5. Use `/llm-wiki:wiki-plan` for planning-stage work when available.

When code behavior, architecture, commands, or dependencies change:

1. Update affected wiki pages.
2. Add a new `wiki/log.d/<timestamp>-<slug>.md` fragment; do not edit compiled `wiki/log.md` directly in feature PRs.
3. Record uncertainty in `wiki/gaps.md`.

Headless wiki refresh is managed by `.llm-wiki/refresh-wiki.sh` and
`.llm-wiki/post-commit-refresh.sh`. Codex is the configured headless wiki agent.
<!-- END LLM WIKI -->
