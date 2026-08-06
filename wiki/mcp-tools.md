---
title: MCP Tools
type: architecture
source: app/tools/**/*.rb, config/initializers/fast_mcp.rb
created: 2026-05-14
updated: 2026-08-05
tags: [mcp, tools, api, agent]
---

# MCP Tools

TLDR: Screenote registers 18 FastMCP tools from `app/tools/`. Current tools cover projects, snapshots, pages, screenshots, multi-viewport upload, annotations, comments, resolution, and collaboration; delete tools and plan/limit tools are still absent.

Source: `app/tools/**/*.rb`, `config/initializers/fast_mcp.rb`

## Transport and Auth

`ProjectAuthTransport` in `config/initializers/fast_mcp.rb` authenticates MCP requests into one immutable `AuthenticatedPrincipal`:

- Project API keys are bound to exactly one project and carry both MCP scopes, but have no user actor. Their issuer remains provenance only; key-authored annotations, replies, and resolution events are attributed to the key instead of impersonating the issuer.
- User-scoped OAuth 2.1 tokens resolve projects from the resource owner's current memberships and require explicit `project_id` on project-specific tools.
- Project-scoped OAuth 2.1 tokens are bound to their consented project. Project-specific tools reject a different `project_id`, `list_projects` returns only the bound project, and `create_project` is forbidden.

The transport accepts request-bound JSON-RPC POSTs only at `/mcp`. FastMCP 1.6's legacy `/mcp/sse` and `/mcp/messages` routes return 404 because its response path broadcasts every result to every registered SSE client; Screenote never calls that broadcaster. This intentionally removes asynchronous MCP resource notifications while preserving tool calls over Streamable HTTP. Canonical path, POST method, remote-IP policy, and origin policy are checked before the 300 requests/minute IP bucket is charged; the IP limit still runs before bearer lookup, followed by a 60 requests/minute API-key or OAuth-token limit. Either limiter fails closed when its store is unavailable. The transport resets `Current.authenticated_principal` before and after every request, including failures.

An application-owned FastMCP server guard replaces dependency-generated backtrace responses with generic JSON-RPC errors. Its sanitizing logger suppresses FastMCP request/result debug and info messages and emits only generic warnings/errors, so screenshot bytes, comments, tool results, bearer tokens, and absolute backtraces do not enter logs.

Project-scoped OAuth listing queries through the user's current memberships again and rechecks the role immediately before serialization. A project object cached when the bearer token was authenticated therefore cannot survive membership removal long enough to appear in `list_projects`.

Every tool declares one exact required scope: read tools require `mcp_read`, while mutations require `mcp_write`; neither scope implies the other. The same declaration supplies the MCP read-only, destructive, idempotent, and open-world safety hints. FastMCP registers only the explicit `Screenote::McpToolRegistry` allowlist, so adding an `ApplicationTool` subclass cannot accidentally expose it. Bootstrap, account administration, recovery, administrator transfer, publication, and secret-management actions are not registered.

The Go CLI in [[api-cli]] does not call MCP. It uses REST `api/v1` so shell and CI users can automate Screenote without an MCP client.

## Tool Inventory

| Tool | Source | Purpose |
|------|--------|---------|
| `list_projects` | `app/tools/list_projects_tool.rb` | List projects visible to the current user |
| `create_project` | `app/tools/create_project_tool.rb` | Create an owned project |
| `list_pages` | `app/tools/list_pages_tool.rb` | List project pages with version counts |
| `create_snapshot` | `app/tools/create_snapshot_tool.rb` | Start a project capture run for a git commit and explicit-offset timestamp |
| `list_screenshots` | `app/tools/list_screenshots_tool.rb` | List screenshots/versions with annotation counts and pagination |
| `create_screenshot` | `app/tools/create_screenshot_tool.rb` | Upload one base64 PNG/JPEG screenshot directly through MCP |
| `create_screenshot_upload` | `app/tools/create_screenshot_upload_tool.rb` | Create one desktop `ScreenshotImage` and return a credential-free URL plus one-time upload bearer |
| `create_multi_viewport_screenshot` | `app/tools/create_multi_viewport_screenshot_tool.rb` | Create one screenshot with 1-3 viewport variants and per-variant URL/bearer pairs |
| `list_annotations` | `app/tools/list_annotations_tool.rb` | List annotations with status, screenshot, viewport, limit, and offset filters |
| `get_annotation` | `app/tools/get_annotation_tool.rb` | Return annotation details, comments, and cropped image data |
| `create_annotation` | `app/tools/create_annotation_tool.rb` | Create point or region annotation; viewport is required for multi-variant screenshots |
| `resolve_annotation` | `app/tools/resolve_annotation_tool.rb` | Mark an annotation resolved and create audit comment |
| `reopen_annotation` | `app/tools/reopen_annotation_tool.rb` | Reopen a resolved annotation with a reason |
| `add_annotation_comment` | `app/tools/add_annotation_comment_tool.rb` | Add a comment to an annotation thread |
| `list_project_members` | `app/tools/list_project_members_tool.rb` | List project members |
| `invite_collaborator` | `app/tools/invite_collaborator_tool.rb` | Send a project invitation |
| `cancel_invitation` | `app/tools/cancel_invitation_tool.rb` | Cancel a pending invitation |
| `remove_project_member` | `app/tools/remove_project_member_tool.rb` | Remove a member from a project |

## Multi-Viewport Semantics

`create_multi_viewport_screenshot` creates a parent [[screenshot]] plus one [[models/screenshot-image]] per requested viewport inside a transaction. Upload URLs are per `ScreenshotImage`, but the endpoint remains `/api/screenshots/:id/upload` for URL shape stability.

For full-project capture runs, `create_snapshot` returns a `snapshot_id`; callers pass that id to each `create_multi_viewport_screenshot` call. Both tools enforce the current project boundary, and the screenshot response echoes the associated `snapshot_id`. Git commits are trimmed and normalized to lowercase before validation. A supplied `taken_at` must be an ISO 8601 timestamp ending in `Z` or an explicit `+/-HH:MM` offset so agent output is independent of the server timezone.

Annotations are scoped by `Annotation#viewport`. `CreateAnnotationTool` defaults only when a screenshot has exactly one available viewport; otherwise it returns an argument error requiring an explicit viewport.

## Known Missing Tools

Source inspection found these planned or todo-backed gaps still absent from `app/tools/`:

- `delete_screenshot`
- `delete_annotation`
- plan/status or usage-limit tools
- batch feedback retrieval

See [[technical-debt]] for the related todo cluster and [[routes]] for non-MCP HTTP surfaces.

See also: [[commands]], [[architecture]], [[models/screenshot]], [[models/annotation]]
