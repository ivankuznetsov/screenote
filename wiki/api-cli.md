---
title: API CLI
type: architecture
source: README.md, cmd/screenote, internal/cli, internal/screenote, app/controllers/api/v1
created: 2026-07-08
updated: 2026-07-08
tags: [cli, api, rest, agents]
---

# API CLI

TLDR: `cmd/screenote` is an installable Go CLI for shell and CI automation. It talks to REST `api/v1`, emits JSON to stdout by default, emits stable JSON errors to stderr, and uses project API keys.

Source: `README.md`, `cmd/screenote`, `internal/cli`, `internal/screenote`, `app/controllers/api/v1`

## Role

MCP remains the richer agent protocol with OAuth/API-key transport and tool semantics. The CLI is the portable shell contract for non-MCP agents and CI jobs. See [[mcp-tools]] and [[routes]].

## Install

```sh
go install github.com/ivankuznetsov/screenote/cmd/screenote@latest
```

Because the Rails repo has a top-level Ruby `vendor/` directory, local Go test/build commands should use:

```sh
GOFLAGS=-mod=mod go test ./...
```

## Configuration

Precedence:

1. Flags: `--api-key`, `--base-url`, `--project`
2. Environment: `SCREENOTE_API_KEY`, `SCREENOTE_BASE_URL`, `SCREENOTE_PROJECT`
3. Config: `~/.config/screenote/config.toml`

`screenote config` prints resolved config as JSON. `screenote config set` writes values noninteractively. Commands never prompt unless a future command explicitly implements `--interactive`.

The base URL should be set explicitly. Current docs use localhost, staging/self-hosted URLs, or the canonical production host `https://screenote.ai` from `config/deploy.yml`.

The CLI is documented around project API keys, but the same REST `Api::V1` bearer layer also accepts scoped OAuth tokens. OAuth use is not currently exposed as a CLI login flow; see [[controllers/api-controllers]] and [[routes]].

## Commands

```sh
screenote project list
screenote page list [--project ID]
screenote screenshot list [--project ID] [--page ID] [--status pending|ready|failed] [--limit N] [--offset N]
screenote screenshot create --title TITLE [--page ID_OR_NAME] [--file PATH|-]
screenote annotation list [--project ID] [--screenshot ID] [--status open|resolved] [--viewport desktop|tablet|mobile]
screenote annotation get --annotation ID
screenote comment add --annotation ID --body TEXT
```

`annotation list` without `--screenshot` lists annotations across all screenshots in the resolved project. The CLI pages through screenshots and per-screenshot annotations, skips screenshots that become inaccessible during aggregation, reports the aggregate total, and applies `--limit`/`--offset` to the aggregate result.

`screenshot create` reads stdin when `--file` is omitted or set to `-`. When uploading a file, the content type is derived from the file extension; for example, `.png` maps to `image/png`. Stdin uploads fall back to `application/octet-stream` and are re-identified server-side from the bytes.

`--page` selects a page by ID when the value is all digits, otherwise it is treated as a page name that is created if it does not exist. Consequently a page literally named `123` cannot be selected by name; an all-digit value always resolves as an ID.

## Error Contract

Successful commands write JSON to stdout. Errors write this shape to stderr:

```json
{"code":"missing_base_url","error":"base URL is required; set --base-url, SCREENOTE_BASE_URL, or config base_url"}
```

Cobra flag parse errors use the stable `invalid_flag` usage error. Invalid base URLs use `invalid_base_url`.

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | OK |
| 1 | Generic error |
| 2 | Usage/config error |
| 3 | Auth/forbidden |
| 4 | Not found |
| 5 | Rate limited |

## Deferred

`annotation resolve`, `annotation reopen`, OAuth browser login, daemon/watch mode, member management, and required multi-viewport upload are future work rather than v1 ship criteria.
