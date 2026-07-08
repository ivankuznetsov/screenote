---
title: MCP Tools
type: architecture
source: app/tools/**/*.rb, config/initializers/fast_mcp.rb
created: 2026-05-14
updated: 2026-05-14
tags: [mcp, tools, api, agent]
---

# MCP Tools

TLDR: Screenote registers 17 FastMCP tools from `app/tools/`. Current tools cover projects, pages, screenshots, multi-viewport upload, annotations, comments, resolution, and collaboration; delete tools and plan/limit tools are still absent.

Source: `app/tools/**/*.rb`, `config/initializers/fast_mcp.rb`

## Transport and Auth

`ProjectAuthTransport` in `config/initializers/fast_mcp.rb` authenticates MCP requests with either:

- Project API keys (`sk_proj_...`): project is implicit through `Current.mcp_project`.
- OAuth 2.1 bearer tokens: user is implicit, and tool calls must pass `project_id`.

The transport rate-limits API keys and OAuth tokens at 60 requests/minute, logs validation failures, reports unexpected errors to Honeybadger, and returns a JSON 429 for rate-limited requests.

## Tool Inventory

| Tool | Source | Purpose |
|------|--------|---------|
| `list_projects` | `app/tools/list_projects_tool.rb` | List projects visible to the current user |
| `create_project` | `app/tools/create_project_tool.rb` | Create an owned project |
| `list_pages` | `app/tools/list_pages_tool.rb` | List project pages with version counts |
| `list_screenshots` | `app/tools/list_screenshots_tool.rb` | List screenshots/versions with annotation counts and pagination |
| `create_screenshot` | `app/tools/create_screenshot_tool.rb` | Upload one base64 PNG/JPEG screenshot directly through MCP |
| `create_screenshot_upload` | `app/tools/create_screenshot_upload_tool.rb` | Create one desktop `ScreenshotImage` and return a signed upload URL |
| `create_multi_viewport_screenshot` | `app/tools/create_multi_viewport_screenshot_tool.rb` | Create one screenshot with 1-3 viewport variants and per-variant signed upload URLs |
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

Annotations are scoped by `Annotation#viewport`. `CreateAnnotationTool` defaults only when a screenshot has exactly one available viewport; otherwise it returns an argument error requiring an explicit viewport.

## Known Missing Tools

Source inspection found these planned or todo-backed gaps still absent from `app/tools/`:

- `delete_screenshot`
- `delete_annotation`
- plan/status or usage-limit tools
- batch feedback retrieval

See [[technical-debt]] for the related todo cluster and [[routes]] for non-MCP HTTP surfaces.

See also: [[commands]], [[architecture]], [[models/screenshot]], [[models/annotation]]
