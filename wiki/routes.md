---
title: Routes
type: architecture
source: config/routes.rb
created: 2026-04-10
updated: 2026-08-06
tags: [routes, api, endpoints, auth]
---

# Routes

TLDR: Core project/review, REST, OAuth, device, and MCP routes are shared. Self-hosted adds bootstrap, recovery, and narrow instance administration; SaaS alone adds registration, billing, Stripe webhook, hosted analytics, landing, and hosted legal routes.

Source: `config/routes.rb`

## App-owned authentication routes

| Path | Purpose | Auth |
|------|---------|------|
| `GET /bootstrap`, `POST /bootstrap` | One-time installation claim | Public, self-hosted only |
| `GET /session/new`, `POST /session`, `DELETE /session` | Local session lifecycle | Public/authenticated as applicable |
| `GET /sign_up`, `POST /sign_up` | Open registration | Public, SaaS only |
| `/passwords*`, `/password-reset` | Password-reset request/consume | Public, mail-enabled only |
| `/magic-link*` | Magic-link request/consume | Public, mail-enabled only |
| `/confirmations*`, `/confirmation` | Email confirmation request/consume | Public, mail-enabled only |
| `GET /auth/:provider/callback` | Verified-email OAuth callback | Public, configured providers only |
| `GET /authentication-links/:purpose` | Sterile fragment landing | Public, allowlisted available purpose only |
| `POST /authentication-links/:purpose/exchange` | Body-only secret exchange into tokenless context | Public, allowlisted available purpose only |
| `GET, POST /invitation-acceptance` | Tokenless invitation review/acceptance | Public |
| `GET, POST /account-recovery` | Tokenless administrator recovery | Public, self-hosted only |

## Web UI Routes

All require authentication unless noted.

### Projects

| Method | Path | Action | Auth |
|--------|------|--------|------|
| GET | `/projects` | index | Member |
| GET | `/projects/new` | new | Member (SaaS quota check; unlimited self-hosted) |
| POST | `/projects` | create | Writable user principal (SaaS quota check; unlimited self-hosted) |
| GET | `/projects/:id` | show | Member |
| GET | `/projects/:id/edit` | edit | Owner |
| PATCH | `/projects/:id` | update | Owner |
| DELETE | `/projects/:id` | destroy | Owner |

### Pages (nested under projects for create, standalone for show/edit/destroy)

| Method | Path | Action | Auth |
|--------|------|--------|------|
| GET | `/projects/:project_id/pages/new` | new | Member |
| POST | `/projects/:project_id/pages` | create | Member |
| GET | `/pages/:id` | show | Member |
| GET | `/pages/:id/edit` | edit | Member |
| PATCH | `/pages/:id` | update | Member |
| DELETE | `/pages/:id` | destroy | Member |

`GET /pages/:id` is the canonical review URL. Optional page-scoped query state
selects a version and viewport:

- `version_id=<screenshot id>` selects that page's exact version; missing,
  deleted, or cross-page ids fall back to the newest version.
- `viewport=desktop|tablet|mobile` selects a viewport when that version has it;
  otherwise the version's default viewport is used.

### Screenshots (nested under pages for create, standalone for show/edit/destroy)

| Method | Path | Action | Auth |
|--------|------|--------|------|
| GET | `/pages/:page_id/screenshots/new` | new | Member |
| POST | `/pages/:page_id/screenshots` | create | Member |
| GET | `/screenshots/:id` | show | Member |
| GET | `/screenshots/:id/viewports/:viewport` | show specific desktop/tablet/mobile variant | Member |
| GET | `/screenshots/:id/edit` | edit | Member |
| PATCH | `/screenshots/:id` | update | Member |
| DELETE | `/screenshots/:id` | destroy | Member |

The two screenshot GET routes remain stable compatibility links. They redirect
to `/pages/:page_id?version_id=:id` and preserve a valid viewport rather than
rendering a second workspace.

### Annotations (nested under screenshots)

| Method | Path | Action | Auth |
|--------|------|--------|------|
| POST | `/screenshots/:screenshot_id/annotations` | create | Member |
| PATCH | `/screenshots/:screenshot_id/annotations/:id` | update | Member |
| DELETE | `/screenshots/:screenshot_id/annotations/:id` | destroy | Member |

### Annotation Comments (nested under annotations)

| Method | Path | Action | Auth |
|--------|------|--------|------|
| POST | `/screenshots/:screenshot_id/annotations/:annotation_id/annotation_comments` | create | Member |

### API Keys (nested under projects)

| Method | Path | Action | Auth |
|--------|------|--------|------|
| GET | `/projects/:project_id/api_keys` | index | Owner |
| GET | `/projects/:project_id/api_keys/new` | new | Owner |
| POST | `/projects/:project_id/api_keys` | create | Owner |
| DELETE | `/projects/:project_id/api_keys/:id` | destroy | Owner |

### Project members and invitations

| Method | Path | Action | Auth |
|--------|------|--------|------|
| GET | `/projects/:project_id/memberships` | index | Member |
| DELETE | `/projects/:project_id/memberships/:id` | destroy | Owner |
| POST | `/projects/:project_id/invitations` | create | Owner |
| DELETE | `/projects/:project_id/invitations/:id` | destroy | Owner |
| GET | `/invitation-acceptance` | tokenless acceptance page | Public |
| POST | `/invitation-acceptance` | accept with session, local password, or verified provider proof | Public |
| GET | `/projects/:project_id/collaborator_suggestions` | autocomplete | Owner |

### Billing

SaaS only; these routes do not exist in self-hosted mode.

| Method | Path | Action | Auth |
|--------|------|--------|------|
| GET | `/subscription` | show | Authenticated |
| POST | `/subscription/checkout` | Stripe checkout redirect | Authenticated |
| POST | `/subscription/portal` | Stripe portal redirect | Authenticated |

### Admin

SaaS only; this hosted analytics authority is unrelated to self-hosted instance administration.

| Method | Path | Action | Auth |
|--------|------|--------|------|
| GET | `/admin/dashboard` | show | Configured SaaS operator only |

### Self-hosted instance administration

| Method | Path | Action | Auth |
|--------|------|--------|------|
| GET | `/instance/accounts` | list accounts | Current installation administrator |
| POST | `/instance/accounts/:id/suspend` | suspend account and revoke credentials | Current installation administrator |
| POST | `/instance/accounts/:id/restore` | restore account | Current installation administrator |
| POST | `/instance/accounts/:id/revoke_credentials` | revoke account credentials | Current installation administrator |
| POST | `/instance/accounts/:id/issue_recovery` | issue private recovery credential | Current installation administrator |
| POST | `/instance/administrator/transfer` | atomically transfer administrator authority | Current installation administrator |

## REST API Routes

### API v1 (Bearer token auth via API key or OAuth)

| Method | Path | Action | Auth |
|--------|------|--------|------|
| GET | `/api/v1/projects` | List API-key project, user-scoped OAuth member projects, or the one project bound to project-scoped OAuth | API key or OAuth `mcp_read` |
| POST | `/api/v1/projects` | Create an owned project within the user's plan quota | User-scoped OAuth `mcp_write` only |
| GET | `/api/v1/projects/:project_id/pages` | List pages with version counts | API key or OAuth `mcp_read` |
| GET | `/api/v1/projects/:project_id/screenshots` | List screenshots with `page_id`, `status`, `limit`, and `offset` filters | API key or OAuth `mcp_read` |
| POST | `/api/v1/projects/:project_id/snapshots` | Prepare or resume a manifest-backed snapshot graph | API key or OAuth `mcp_write` |
| GET | `/api/v1/projects/:project_id/snapshots/:id` | Read snapshot and image recovery state | API key or OAuth `mcp_read` |
| PUT | `/api/v1/projects/:project_id/screenshot_images/:id` | Stream content-bound bytes into a prepared viewport image | API key or OAuth `mcp_write` |
| POST | `/api/v1/screenshots` | Direct multipart screenshot upload | API key or OAuth `mcp_write` |
| GET | `/api/v1/screenshots/:screenshot_id/annotations` | List annotations with `status`, `viewport`, `limit`, and `offset` filters | API key or OAuth `mcp_read` |
| GET | `/api/v1/annotations/:id` | Get annotation details, comments, and best-effort crop data | API key or OAuth `mcp_read` |
| POST | `/api/v1/annotations/:annotation_id/comments` | Add an API-key-authored or OAuth-user-authored annotation comment | API key or OAuth `mcp_write` |
| POST | `/api/v1/annotations/:annotation_id/resolve` | Idempotently resolve an annotation and create its audit comment | API key or OAuth `mcp_write` |

API-key auth is project-scoped. If `:project_id` does not match the key's project, the v1 API returns a stable JSON error with `code: "forbidden"` rather than crossing project boundaries. OAuth project-scoped calls require explicit `project_id` where the route does not already carry it, and the authenticated user must be a project member. Project listing also returns only the bound project for a project-scoped token. Deleting that project deletes its scoped OAuth grants and tokens rather than widening them to user scope.

Project creation is intentionally different from project-scoped operations: API keys and project-scoped OAuth tokens cannot create another project. A user-scoped OAuth token needs `mcp_write`; successful creation returns `201` with the standard project representation and `role: "owner"`. Free-plan quota exhaustion returns `403` with `code: "project_limit_reached"`.

Annotation resolution accepts optional string `comment`; an omitted or blank value records `Marked as resolved`, while arrays and objects receive `422 validation_failed`. A first resolution returns `operation: "resolved"`, while a retry returns `operation: "already_resolved"` without creating another audit comment. Locking lives at the shared annotation model boundary so stale REST, web, and legacy MCP writers cannot duplicate a resolution comment. Project-scoped OAuth tokens are bound to the project recorded on the token and cannot select another project through `project_id`.

### Upload API (single-use bearer, no persistent auth)

| Method | Path | Action | Auth |
|--------|------|--------|------|
| PUT | `/api/screenshots/:id/upload` | Binary upload with one-time token | `Authorization: Bearer <upload token>` |

The upload route keeps the parent screenshot URL shape, but its separate bearer resolves to a specific `ScreenshotImage`, allowing multi-viewport uploads to PUT desktop/tablet/mobile binaries independently. Query-string credentials are rejected.

## OAuth 2.1 Endpoints (Doorkeeper)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/oauth/authorize` | Authorization endpoint |
| POST | `/oauth/token` | Token endpoint |
| POST | `/oauth/revoke` | Token revocation |
| POST | `/oauth/register` | Dynamic client registration (RFC 7591; always SaaS, only after self-hosted claim) |
| POST | `/oauth/authorize_device` | Start an OAuth device authorization (RFC 8628, public clients, IP limited) |
| GET | `/oauth/device` | Authenticated one-time-code entry and approval page |
| POST | `/oauth/device` | CSRF-protected explicit approval or denial |
| GET | `/.well-known/oauth-protected-resource` | Resource metadata (RFC 9728) |
| GET | `/.well-known/oauth-authorization-server` | Server metadata (RFC 8414) |

## Static Pages (Public)

| Method | Path | Action |
|--------|------|--------|
| GET | `/` | SaaS landing page; self-hosted bootstrap/sign-in root |
| GET | `/dashboard` | Project index |
| GET | `/help` | CLI install, OAuth sign-in, and command guide |
| GET | `/terms` | Hosted Terms of Service (SaaS only) |
| GET | `/privacy` | Hosted Privacy Policy (SaaS only) |

## Webhook

SaaS only.

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/stripe/webhooks` | Stripe webhook receiver |

## Health Check

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/up` | Load balancer health check |

See also: [[architecture]], [[controllers/web-controllers]], [[controllers/api-controllers]], [[mcp-tools]]
