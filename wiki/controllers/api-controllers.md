---
title: API Controllers
type: controller
source: app/controllers/api/
created: 2026-04-10
updated: 2026-07-08
tags: [controller, api, rest, bearer-auth]
---

# API Controllers

TLDR: REST API for agent/programmatic access. Bearer token authentication accepts project API keys and scoped OAuth tokens. Two namespaces: `Api` (upload endpoint) and `Api::V1` (versioned CRUD).

Source: `app/controllers/api/`

## Api::BaseController

Source: `app/controllers/api/base_controller.rb`

Base class for authenticated API endpoints. Inherits from `ActionController::API` (no view rendering, no CSRF).

**before_actions:**
- `authenticate_bearer!` -- Extracts bearer token from `Authorization`, calls `Api::BearerAuthenticator`, and returns 401 if the token is invalid, expired, revoked, or missing.

**Rescue handlers:**
- `ActiveRecord::RecordInvalid` -> 422 with error messages
- `ActiveRecord::RecordNotFound` -> 404

**Provides:**
- `current_api_key` -- The authenticated ApiKey
- `current_oauth_token` -- The authenticated Doorkeeper access token
- `current_user` -- The OAuth resource owner for OAuth-authenticated requests
- `current_project` -- The project associated with the API key
- Stable JSON error rendering with `error` and machine-readable `code`
- `require_current_project!` guard for project-scoped nested routes
- `require_scope!` guard for OAuth scopes (`mcp_read` and `mcp_write`); API-key requests bypass scope checks
- Shared pagination coercion for `limit` and `offset` params

For API-key requests, `require_current_project!` only returns a project when the key has a present project and the requested `project_id` is blank or matches that project. Otherwise it returns a stable forbidden JSON error. This includes the `replace-screenote-cli-api-key-260708-545b` guard for a stale or otherwise projectless API key, preventing a 500 from `current_project.id`.

For OAuth requests, `project_id` is required on project-scoped endpoints. The controller looks up the project, verifies `Project#member?(current_user)`, stores it as `current_project`, and returns `missing_project` or `forbidden` JSON when the project is absent or inaccessible.

---

## Api::V1::ProjectsController

Source: `app/controllers/api/v1/projects_controller.rb`

**Actions:** index

Returns visible projects for the bearer credential.

- API-key auth is project-authoritative, so the response is a one-project list with role `api_key`.
- OAuth auth requires `mcp_read` and returns all projects where `current_user` has a `ProjectMembership`, with each membership role merged into the project payload.
- OAuth project listing preloads memberships and computes `screenshot_count` for all returned projects with one grouped query through `Screenshot.joins(:page)`, then passes the precomputed count into `Api::V1::ContractSerializer.project`.

---

## Api::V1::PagesController

Source: `app/controllers/api/v1/pages_controller.rb`

**Actions:** index

Lists pages for the resolved project with version counts and page URLs. API-key requests must match the key's project; OAuth requests must provide an accessible `project_id`.

---

## Api::V1::ScreenshotsController

Source: `app/controllers/api/v1/screenshots_controller.rb`

**Inherits from:** `Api::BaseController`

**Actions:** index, create

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| index | GET | `/api/v1/projects/:project_id/screenshots` | Lists screenshots with filters and pagination |
| create | POST | `/api/v1/screenshots` | Uploads screenshot with image file |

- Requires `image` parameter (file upload)
- For create, `page`/`page_id` selects a page by numeric ID or name; absent page input falls back to the screenshot title and creates the page if needed
- Uses `Screenshot.create_with_image!`, which creates the parent screenshot and a desktop [[models/screenshot-image]]
- List supports `page_id`, `status`, `limit`, and `offset`
- Create returns `screenshot_id`, `page_id`, `status`, `annotate_url`, and primary image metadata

---

## Api::V1::AnnotationsController

Source: `app/controllers/api/v1/annotations_controller.rb`

**Inherits from:** `Api::BaseController`

**Actions:** index, show

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| index | GET | `/api/v1/screenshots/:screenshot_id/annotations` | Lists annotations |
| show | GET | `/api/v1/annotations/:id` | Annotation detail with comments and best-effort crop data |

- Scopes to current project via join through screenshots
- Supports `?status=open|resolved`, `?viewport=desktop|tablet|mobile`, `?limit=`, and `?offset=` filters
- Returns serialized annotations via `Annotation#as_api_json`

---

## Api::V1::AnnotationCommentsController

Source: `app/controllers/api/v1/annotation_comments_controller.rb`

**Actions:** create

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| create | POST | `/api/v1/annotations/:annotation_id/comments` | Creates an API-key-authored or OAuth-user-authored annotation comment |

---

## Api::ScreenshotUploadsController

Source: `app/controllers/api/screenshot_uploads_controller.rb`

**Inherits from:** `ActionController::API` (NO bearer auth -- uses upload tokens instead)

**Actions:** update

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| update | PUT | `/api/screenshots/:id/upload` | Binary body upload |

- **Rate limited:** 20 requests per hour per IP
- Validates one-time upload token generated by the target [[models/screenshot-image]]
- Reads raw request body as binary image data
- Validates: token validity, image not already uploaded, mime type (PNG/JPEG), body not empty, size under 20MB
- Attaches to the resolved ScreenshotImage and enqueues `ScreenshotDimensionJob` for that image
- Returns `screenshot_id` and `annotate_url`

## Authentication Summary

| Endpoint | Auth Method |
|----------|------------|
| `Api::V1::*` | Bearer token via `Authorization: Bearer ...`; accepts ApiKey tokens or Doorkeeper OAuth tokens |
| `Api::ScreenshotUploadsController` | One-time upload token via query param `?token=...` |

API keys are project-scoped and do not use OAuth scopes. OAuth tokens must carry `mcp_read` for read endpoints and `mcp_write` for write endpoints.

See also: [[routes]], [[models/api-key]], [[models/screenshot]], [[models/screenshot-image]], [[controllers/web-controllers]]
