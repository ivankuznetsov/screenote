# Screenote

Screenote is a Rails visual feedback app for screenshots, annotations, and agent workflows. The browser app is the review surface, and the Go CLI is the shell and automation contract.

## Go CLI

Install:

```sh
go install github.com/ivankuznetsov/screenote-cli/cmd/screenote@latest
```

Authorize the CLI with OAuth against a self-hosted, local, staging, or production base URL:

```sh
screenote --base-url https://screenote.ai login
```

The default login opens a browser and uses PKCE with a loopback callback. SSH, tmux, and other headless sessions can use the OAuth device flow instead:

```sh
screenote --base-url https://screenote.ai login --device
```

Device login prints a one-time code and authorization link that can be approved in any browser. It does not bind a callback port or require SSH forwarding. Both login methods store OAuth credentials with owner-only permissions; `screenote logout` removes them.

Configuration precedence for non-secret settings is:

1. Flags: `--base-url`, `--project`
2. Environment: `SCREENOTE_BASE_URL`, `SCREENOTE_PROJECT`
3. Config file: `~/.config/screenote/config.toml`

Ordinary commands never prompt or open a browser. Only explicit `screenote login` starts OAuth. Project-scoped commands require `--project`, `SCREENOTE_PROJECT`, or config `project`.

Examples:

```sh
screenote --base-url http://localhost:3005 login
screenote project list
screenote --project 7 page list
screenote --project 7 screenshot create --title "Homepage" --file screenshot.png
cat screenshot.png | screenote --project 7 screenshot create --title "Homepage"
screenote --project 7 screenshot list --status ready --limit 25
screenote --project 7 annotation list --screenshot 123 --status open
screenote --project 7 annotation get --annotation 456
screenote --project 7 comment add --annotation 456 --body "Fix pushed in abc123"
screenote --project 7 snapshot --manifest snapshot.json
```

`snapshot` publishes a browser-free multi-page capture from locally produced PNG/JPEG files. An unchanged manifest is resumable after upload, transport, or processing failures; see the public CLI's [snapshot manifest reference](https://github.com/ivankuznetsov/screenote-cli/blob/main/docs/snapshot-manifest.md) for the versioned contract.

Successful commands write JSON to stdout. Errors write JSON to stderr:

```json
{"code":"missing_base_url","error":"base URL is required; set --base-url, SCREENOTE_BASE_URL, or config base_url"}
```

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | OK |
| 1 | Generic error |
| 2 | Usage/config error |
| 3 | Authentication or authorization failed |
| 4 | Not found |
| 5 | Rate limited |

## Development

Rails tests:

```sh
bin/rails test
```

Go tests:

```sh
GOFLAGS=-mod=mod go test ./...
```

`GOFLAGS=-mod=mod` is required because this Rails repo has a top-level `vendor/` directory that is not a Go vendor tree.
