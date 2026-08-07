# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

Screenote is a hosted and self-hostable visual feedback tool for teams and
coding agents. People upload screenshots and annotate them with Figma-style
comments. The public agent contract is the JSON Screenote CLI plus its
companion agent skill/plugin: agents publish captures, retrieve annotations and
available image crops, and reply through CLI commands that use the REST API
internally. A legacy MCP runtime remains in the source tree, but it is not the
supported public integration surface.

### Core Concepts

- **Screenshot** — an uploaded image that serves as the canvas for feedback
- **Annotation** — a comment pinned to a point or rectangular region of a screenshot (percentage-based coordinates + text)
- **Screenote CLI** — the machine-readable publish and feedback contract used by automation and the agent skill/plugin
- **Project** — groups screenshots and members; browser and CLI authorization remains project-scoped

### Three Core Workflows

1. **Upload Screenshot**: User or agent uploads image -> teammate annotates in browser -> agent collects through the CLI
2. **Enter URL** (future): User enters URL -> server captures page -> User annotates -> Agent collects
3. **Agent-initiated** (killer feature): Agent screenshots localhost -> uploads with the CLI -> human annotates -> agent reads feedback with the CLI -> agent fixes -> repeat

### Authentication

Uses `rails_simple_auth` gem with:
- Email/password authentication
- Magic link (passwordless) sign-in
- Google and GitHub OAuth (via OmniAuth)
- Email confirmation
- Separate `auth` layout for auth pages (avoids Rails Engine namespace issues)

Browser sessions use `rails_simple_auth`. CLI and agent access uses Doorkeeper
OAuth, including browser and device login, then project-scoped REST
authorization. Do not design new public agent workflows around MCP or assume a
project API key is the only authorization model.

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

Runtime requirements depend on the edition. `config/deploy.yml` is the public
self-hosted Kamal starter; `config/deploy.saas.yml` is the complete hosted
service configuration. Keep those contracts separate.

```bash
# Common deployment identity
SCREENOTE_EDITION=self_hosted # or saas
SCREENOTE_BASE_URL=https://screenote.example.com

# Optional auth and email providers
MAILER_FROM=noreply@screenote.app
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GITHUB_CLIENT_ID=...
GITHUB_CLIENT_SECRET=...

# Self-hosted storage (local is the default; S3-compatible is optional)
SCREENOTE_STORAGE=local # or s3
SCREENOTE_S3_ENDPOINT=...
SCREENOTE_S3_REGION=...
SCREENOTE_S3_BUCKET=...
SCREENOTE_S3_PREFIX=...

# Hosted SaaS storage
RABATA_ACCESS_KEY_ID=...
RABATA_SECRET_ACCESS_KEY=...
RABATA_BUCKET=...
RABATA_REGION=...
RABATA_ENDPOINT=...

# Hosted SaaS PostgreSQL roles
DATABASE_URL=postgresql://...
CACHE_DATABASE_URL=postgresql://...
QUEUE_DATABASE_URL=postgresql://...
CABLE_DATABASE_URL=postgresql://...

# Optional for self-hosting; required by the hosted SaaS configuration
HONEYBADGER_API_KEY=...
HONEYBADGER_JS_API_KEY=...
```

Self-hosting uses four SQLite databases (primary, cache, queue, and cable) on
the durable `/rails/storage` volume. It does not require PostgreSQL, Rabata, or
Honeybadger. Local screenshot storage is the default; generic S3-compatible
storage, SMTP, social OAuth, and monitoring are opt-in and must be configured
completely when enabled. Hosted `screenote.ai` uses four PostgreSQL roles,
Rabata object storage, and Honeybadger alongside its other required providers.

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
- Ruby 3.4.10+
- Rails 8.1.2+
- SQLite (development, test, and self-hosted production); PostgreSQL (hosted SaaS production)
- Active Storage with local files by default for self-hosting, optional generic S3, and Rabata for hosted SaaS
- Honeybadger is optional for self-hosting and required for hosted SaaS
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
- Report errors to the configured monitoring provider; self-hosting may run with monitoring disabled
- Never store images in the database — use the configured Active Storage service (local or S3-compatible for self-hosting, Rabata for hosted SaaS)

### Deployment (Kamal)

Use the repository wrappers so the self-hosted and SaaS configurations cannot
be mixed:

```bash
# Public self-hosted starter
bin/kamal setup
bin/kamal deploy
bin/kamal console
bin/kamal logs

# Hosted screenote.ai only
bin/kamal-saas deploy
bin/kamal-saas console
bin/kamal-saas logs
```

On a supported self-hosted tag, `bin/kamal setup`, `deploy`, and `redeploy`
must validate the immutable public release evidence, mirror the exact qualified
image through the loopback registry, and run Kamal with `--skip-push`. Do not
bypass that path. `SCREENOTE_KAMAL_SOURCE_BUILD=1` is only for explicitly
unsupported development/custom images.

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
