---
title: API CLI
type: architecture
source: README.md, cmd/screenote, internal/cli, internal/screenote, app/controllers/api/v1
created: 2026-07-08
updated: 2026-07-13
tags: [cli, api, rest, agents]
---

# API CLI

TLDR: `cmd/screenote` is an installable Go CLI for shell and automation. It talks to REST `api/v1`, emits JSON to stdout by default, emits stable JSON errors to stderr, and signs in through OAuth.

Source: `README.md`, `cmd/screenote`, `internal/cli`, `internal/screenote`, `app/controllers/api/v1`

## Role

The CLI is the portable shell contract for agents and automation. CLI-facing authentication is OAuth-only in user documentation; server-side API keys remain available for direct REST integrations. See [[routes]].

## Install

Go 1.26 or newer is required.

```sh
go install github.com/ivankuznetsov/screenote-cli/cmd/screenote@latest
```

Because the Rails repo has a top-level Ruby `vendor/` directory, local Go test/build commands should use:

```sh
GOFLAGS=-mod=mod go test ./...
```

## Configuration

Precedence:

1. Flags: `--base-url`, `--project`
2. Environment: `SCREENOTE_BASE_URL`, `SCREENOTE_PROJECT`
3. Config: `~/.config/screenote/config.toml`
4. OAuth credentials stored by `screenote login`

`screenote config` prints resolved non-secret config as JSON and never prints stored login secrets. `screenote config set` writes values noninteractively. Config writes enforce owner-only permissions even for a pre-existing hand-authored file. Ordinary commands never prompt or open a browser; only explicit `screenote login` starts an interactive OAuth flow.

The base URL should be set explicitly. Current docs use localhost, staging/self-hosted URLs, or the canonical production host `https://screenote.ai` from `config/deploy.yml`.

The default login uses the OAuth authorization-code flow with PKCE and a loopback redirect:

```sh
screenote --base-url https://screenote.ai login
screenote logout
```

SSH, tmux, and other headless sessions can use the device-authorization flow instead:

```sh
screenote --base-url https://screenote.ai login --device
```

The device flow prints a one-time code and authorization link for approval on any device, then waits for authorization in the terminal. It does not bind a local callback port or require SSH port forwarding.

Login stores the authorized base URL alongside its single credential set, so a `--base-url` or environment override becomes the configured server for later commands. When browser launch is unavailable, stderr receives a JSON `browser_open_failed` message with `authorization_url` for manual continuation. Default REST and OAuth HTTP clients use a 30-second timeout; command cancellation still propagates through OAuth discovery, registration, exchange, and refresh.

## Commands

```sh
screenote project list
screenote project create --name NAME
screenote config
screenote login [--device]
screenote logout
screenote page list --project ID
screenote screenshot list --project ID [--page ID] [--status pending|ready|failed] [--limit N] [--offset N]
screenote screenshot create --project ID --title TITLE [--page ID_OR_NAME] [--file PATH|-]
screenote annotation list --project ID [--screenshot ID] [--status open|resolved] [--viewport desktop|tablet|mobile]
screenote annotation get --project ID --annotation ID [--crop-file PATH]
screenote comment add --project ID --annotation ID --body TEXT
screenote annotation resolve --project ID --annotation ID [--comment TEXT]
screenote snapshot --project ID --manifest PATH
```

User-global commands are `project list`, `project create`, `config`, `login`, and `logout`. Project-scoped commands require project selection through `--project`, `SCREENOTE_PROJECT`, or config `project`; missing project is a JSON stderr usage/config error with code `missing_project` and exit code 2.

`annotation list` without `--screenshot` lists annotations across all screenshots in the resolved project. The CLI pages through screenshots and per-screenshot annotations, skips screenshots that become inaccessible during aggregation, reports the aggregate total, and applies `--limit`/`--offset` to the aggregate result.

`annotation get --crop-file PATH` fully validates and writes the PNG crop atomically with owner-only permissions, returns the local path in JSON, and omits the base64 field. `annotation resolve` is idempotent: the initial response reports `resolved`, while a replay reports `already_resolved` without another audit comment.

`screenshot create` reads stdin when `--file` is omitted or set to `-`. When uploading a file, the content type is derived from the file extension; for example, `.png` maps to `image/png`. Stdin uploads fall back to `application/octet-stream` and are re-identified server-side from the bytes.

`--page` selects a page by ID when the value is all digits, otherwise it is treated as a page name that is created if it does not exist. Consequently a page literally named `123` cannot be selected by name; an all-digit value always resolves as an ID.

## Error Contract

Successful commands write JSON to stdout. Errors write this shape to stderr:

```json
{"code":"missing_base_url","error":"base URL is required; set --base-url, SCREENOTE_BASE_URL, or config base_url"}
```

Cobra flag parse errors use the stable `invalid_flag` usage error. Invalid base URLs use `invalid_base_url`. Missing or expired OAuth credentials return exit code 3.

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | OK |
| 1 | Generic error |
| 2 | Usage/config error |
| 3 | Auth/forbidden |
| 4 | Not found |
| 5 | Rate limited |

## Snapshot REST Foundation

The private service now exposes project-scoped prepare and show resources for a manifest-driven public CLI. Preparation accepts normalized page/title/viewport entries, expected PNG/JPEG types, image content SHA-256 values, and opaque relative-file reference hashes. The server verifies the aggregate manifest identity before creating the complete Snapshot -> Screenshot -> ScreenshotImage graph in one transaction.

An identical request resumes the same graph and returns image-level `awaiting_upload`, `processing`, `failed`, or `ready` state plus a snapshot-filtered project review URL. Replay also ensures every attached pending image has dimension processing scheduled, recovering when attachment commit succeeded but the original queue enqueue failed. Overlapping jobs for the same attachment blob generation are discarded by the production queue; a replacement blob receives a distinct generation, and stale analysis cannot update it. A changed contract gets a different manifest identity; a stored graph that no longer matches its identity returns `manifest_conflict`. Readable client file paths never enter the REST request or response.

Prepared image bytes upload through a separate bearer-authenticated raw-body route. It uses bounded disk-backed streaming, verifies actual PNG/JPEG bytes against the declared and prepared type, verifies SHA-256 content identity, and treats an identical retry as success. Failed dimension processing can be retried without creating another blob. The existing MCP signed-upload route remains unchanged.

The CLI source is now canonical in the public `github.com/ivankuznetsov/screenote-cli` repository. Its language-neutral digest vectors are executed by both Go and the production Rails digest implementation. Blocking service CI pins exact supported public CLI commits; a scheduled service workflow checks the public CLI `main` branch for forward drift. The private copy remains temporarily present until the separately scoped cleanup removes it after public CLI merge and production verification.

## Workflow REST Parity

The REST service exposes the missing write contracts needed by CLI workflow commands:

- `POST /api/v1/projects` creates a project for a user-scoped OAuth `mcp_write` token, enforces the account's plan quota under a user lock, and returns the standard project JSON with `role: owner` and HTTP `201`. API keys and project-scoped OAuth tokens cannot create projects.
- `POST /api/v1/annotations/:annotation_id/resolve` accepts explicit OAuth project context plus an optional `comment`, or uses the API key's bound project. It creates a user- or API-key-authored resolved audit comment once and returns `already_resolved` without duplicating that comment on retries.

Project-scoped OAuth tokens are bound to the token's `project_id` throughout REST authorization: project listing returns only that bound member project, and passing a different project id cannot widen the token even when its user belongs to both projects. Deleting the bound project also deletes its scoped grants and access tokens instead of converting those bearer credentials into user-scoped access.

## Deferred

`annotation reopen`, snapshot-scoped feedback retrieval, daemon/watch mode, member management, and required multi-viewport upload remain future work rather than current REST contracts. Public CLI command/help wiring for project creation and annotation resolution is maintained in the public CLI and agent-plugin repositories; this service page documents the server contract they can consume.
