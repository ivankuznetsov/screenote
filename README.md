# Screenote

Screenote is a Rails visual feedback app for screenshots, annotations, and agent workflows. The browser app is the review surface, MCP is the rich agent protocol, and the Go CLI is the shell/CI REST contract.

## Go CLI

Install:

```sh
go install github.com/ivankuznetsov/screenote/cmd/screenote@latest
```

Configure a self-hosted, local, staging, or production base URL explicitly. CI and agents can use a pre-provisioned OAuth bearer token:

```sh
screenote config set --base-url https://screenote.ai --token "$SCREENOTE_TOKEN"
screenote config
```

Developers can also store OAuth login credentials explicitly:

```sh
screenote --base-url https://screenote.ai login
screenote logout
```

Configuration precedence is:

1. Flags: `--token`, `--base-url`, `--project`
2. Environment: `SCREENOTE_TOKEN`, `SCREENOTE_BASE_URL`, `SCREENOTE_PROJECT`
3. Config file: `~/.config/screenote/config.toml`
4. Stored login credentials from `screenote login`

Ordinary commands never prompt or open a browser. Project-scoped commands require `--project`, `SCREENOTE_PROJECT`, or config `project`.

Examples:

```sh
screenote --base-url http://localhost:3005 --token "$SCREENOTE_TOKEN" project list
screenote --project 7 page list
screenote --project 7 screenshot create --title "Homepage" --file screenshot.png
cat screenshot.png | screenote --project 7 screenshot create --title "Homepage"
screenote screenshot list --status ready --limit 25
screenote --project 7 annotation list --screenshot 123 --status open
screenote --project 7 annotation get --annotation 456
screenote --project 7 comment add --annotation 456 --body "Fix pushed in abc123"
```

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
| 3 | Auth/forbidden, including invalid or expired tokens |
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
