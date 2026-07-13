---
title: API Controllers
type: controller
source: app/controllers/api/
created: 2026-04-10
updated: 2026-07-10
tags: [controller, api, rest, bearer-auth]
---

# API Controllers

TLDR: REST API for agent/programmatic access. REST v1 accepts project API keys and Doorkeeper OAuth bearer tokens; the upload endpoint remains signed-token based.

Source: `app/controllers/api/`

## Api::BaseController

Source: `app/controllers/api/base_controller.rb`

Base class for authenticated API endpoints. Inherits from `ActionController::API` (no view rendering, no CSRF).

**before_actions:**
- `authenticate_bearer!` -- Extracts bearer token from `Authorization`, validates an active `ApiKey` or a live Doorkeeper access token, returns 401 JSON `unauthorized` if invalid

**Rescue handlers:**
- `ActiveRecord::RecordInvalid` -> 422 with error messages
- `ActiveRecord::RecordNotFound` -> 404

**Provides:**
- `current_api_key` -- The authenticated ApiKey
- `current_oauth_token` / `current_user` -- OAuth request identity
- `current_project` -- The API-key project or selected OAuth member project
- Stable JSON error rendering with `error` and machine-readable `code`
- `require_current_project!` guard for API-key scoped nested routes
- Shared pagination coercion for `limit` and `offset` params

---

## Api::V1::ProjectsController

Source: `app/controllers/api/v1/projects_controller.rb`

**Actions:** index, create

API-key auth returns the project bound to the API key with role `api_key`. User-scoped OAuth with `mcp_read` returns all projects visible through the authenticated user's memberships with membership roles; project-scoped OAuth returns only its bound project after rechecking membership.

Creation accepts a flat `name`, requires a user-scoped OAuth token with `mcp_write`, serializes the created project with `role: owner`, and relies on the Project callback to create the owner membership. The check and write run under the user row lock so concurrent free-plan requests cannot exceed the project quota. API keys and project-scoped OAuth tokens receive `forbidden`; quota exhaustion receives `project_limit_reached`.

---

## Api::V1::PagesController

Source: `app/controllers/api/v1/pages_controller.rb`

**Actions:** index

Lists pages with version counts and page URLs. API-key requests require `:project_id` to match the key's project. OAuth requests require `mcp_read` and membership in the selected `:project_id`.

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
- OAuth list requires `mcp_read`; OAuth create requires `mcp_write` and explicit `project_id`

## Api::V1::SnapshotsController

Source: `app/controllers/api/v1/snapshots_controller.rb`, `app/services/snapshots/prepare_upload.rb`

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| create | POST | `/api/v1/projects/:project_id/snapshots` | Validates and atomically prepares or resumes a manifest-backed capture graph |
| show | GET | `/api/v1/projects/:project_id/snapshots/:id` | Returns aggregate lifecycle, image-level recovery state, and review URL |

- Create requires API-key access or OAuth `mcp_write`; show requires API-key access or OAuth `mcp_read`.
- The preparation service normalizes the flat manifest contract, verifies a language-neutral length-prefixed SHA-256 digest, groups page/title viewport entries, and performs no writes until the full contract passes validation.
- Identical requests return the existing graph. Database uniqueness plus replay verification handle lost responses and concurrent callers; replay also re-enqueues dimension processing for attached pending images so a queue failure after attachment commit cannot strand the capture. Stored membership drift returns JSON `manifest_conflict` rather than repairing or mixing graphs.
- Preparation is limited per authenticated bearer/project, with unauthenticated attempts keyed by IP and project.
- Responses expose stable snapshot, screenshot, and ScreenshotImage identities without returning local file references.

## Api::V1::ScreenshotImagesController

Source: `app/controllers/api/v1/screenshot_images_controller.rb`, `app/services/snapshots/attach_image.rb`

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| update | PUT | `/api/v1/projects/:project_id/screenshot_images/:id` | Streams and attaches prepared manifest image bytes |

- Requires API-key project access or OAuth `mcp_write` membership.
- Rejects a declared body over 20 MB before reading and stops a chunked body as soon as it crosses the bound. All bodies stream through an automatically unlinked temporary file while SHA-256 is computed.
- Marcel detects actual bytes without trusting extensions or the declared header. The detected type must be PNG/JPEG and match both `Content-Type` and the prepared expected type; the computed SHA must match the prepared content identity.
- A row lock makes identical concurrent or lost-response retries converge on one Active Storage attachment. An attached pending/ready image returns `already_uploaded`; an attached failed image returns to pending and re-enqueues dimension processing without replacing its blob.
- The authenticated-project upload budget is 250 requests/hour, covering a 100-image manifest plus a full retry with margin. Unauthenticated attempts are keyed by IP and project.

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
- OAuth requests require `mcp_read` and explicit `project_id`

---

## Api::V1::AnnotationCommentsController

Source: `app/controllers/api/v1/annotation_comments_controller.rb`

**Actions:** create

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| create | POST | `/api/v1/annotations/:annotation_id/comments` | Creates an API-key-authored or OAuth-user-authored annotation comment |

- OAuth requests require `mcp_write` and explicit `project_id`

---

## Api::V1::AnnotationResolutionsController

Source: `app/controllers/api/v1/annotation_resolutions_controller.rb`

**Actions:** create

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| create | POST | `/api/v1/annotations/:annotation_id/resolve` | Idempotently resolves project-scoped feedback and returns the standard annotation plus resolution comment |

- Requires API-key access or OAuth `mcp_write`; OAuth callers pass explicit `project_id`.
- Attributes the transactional resolution comment to the current API key or OAuth user.
- Delegates to the model's locked resolution boundary so REST, web, and legacy MCP writers cannot create duplicate resolved audit comments from stale instances.
- Rejects non-string `comment` parameters with the stable `validation_failed` HTTP `422` envelope; omitted and blank strings retain the default comment.
- Returns `operation: resolved` on the state transition and `operation: already_resolved` on replay.
- Project-scoped OAuth tokens cannot select a different project even when the user belongs to both projects.

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
| `Api::V1::*` | Bearer token via project API key or Doorkeeper OAuth access token |
| `Api::ScreenshotUploadsController` | One-time upload token via query param `?token=...` |

OAuth REST scopes reuse MCP scopes: read endpoints require `mcp_read`, and write endpoints require `mcp_write`. OAuth project-scoped endpoints require explicit project context and membership validation; object IDs alone are not enough.

See also: [[routes]], [[models/api-key]], [[models/screenshot]], [[models/screenshot-image]], [[controllers/web-controllers]]
