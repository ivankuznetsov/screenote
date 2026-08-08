---
title: Interaction Surface
type: commands
source: app/controllers/**, github.com/ivankuznetsov/screenote-cli, config/routes.rb, bin/brakeman, bin/bundler-audit
created: 2026-05-14
updated: 2026-08-08
tags: [commands, api]
---

**TLDR**: External interaction surface is derived from routes, controllers, commands, and plugin surfaces.

## Go CLI

Canonical source: the public `github.com/ivankuznetsov/screenote-cli` repository. The private `cmd/screenote` and `internal/` copy is transitional and is not the installation source.

With Go 1.26 or newer installed, install the CLI with:

```sh
go install github.com/ivankuznetsov/screenote-cli/cmd/screenote@<release-cli-tag>
```

The first supported Screenote release and its immutable CLI tag are still
pending. The CLI `main` branch is useful for development, but it is not a
supported release artifact.

The CLI talks to the REST API, not MCP. Public CLI authentication is OAuth-only: `screenote login` uses authorization code with PKCE, while `screenote login --device` supports SSH, tmux, containers, and other headless sessions without port forwarding. It emits JSON to stdout for successful commands and stable JSON errors to stderr. See [[api-cli]] for command examples, config precedence, and exit codes.

Implemented command groups:

| Command | Purpose |
| --- | --- |
| `screenote config` / `screenote config set` | Print or write noninteractive config |
| `screenote login [--device]` / `screenote logout` | Create or remove refreshable OAuth credentials |
| `screenote project list` | List projects available to the signed-in user |
| `screenote page list` | List pages for the selected project |
| `screenote screenshot list` | List screenshots with filters and pagination |
| `screenote screenshot create` | Multipart upload from file or stdin |
| `screenote snapshot` | Validate, publish, and resume a manifest-driven multi-page capture |
| `screenote annotation list` | List screenshot annotations, or traverse project screenshots when `--screenshot` is omitted |
| `screenote annotation get` | Get annotation details plus comments and crop data |
| `screenote annotation resolve` | Idempotently resolve an annotation with an optional final comment |
| `screenote comment add` | Add an annotation comment |

Annotation reopening remains available in the web review UI and is not yet a
CLI command.

## Source Files

- `app/controllers/admin/dashboard_controller.rb`
- `app/controllers/annotation_comments_controller.rb`
- `app/controllers/annotations_controller.rb`
- `app/controllers/api/base_controller.rb`
- `app/controllers/api/screenshot_uploads_controller.rb`
- `app/controllers/api/v1/annotation_comments_controller.rb`
- `app/controllers/api/v1/annotation_resolutions_controller.rb`
- `app/controllers/api/v1/annotations_controller.rb`
- `app/controllers/api/v1/pages_controller.rb`
- `app/controllers/api/v1/projects_controller.rb`
- `app/controllers/api/v1/screenshots_controller.rb`
- `app/controllers/api_keys_controller.rb`
- `app/controllers/application_controller.rb`
- `app/controllers/collaborator_suggestions_controller.rb`
- `app/controllers/concerns/.keep`
- `app/controllers/concerns/project_authorization.rb`
- `app/controllers/invitation_acceptances_controller.rb`
- `app/controllers/oauth/authorizations_controller.rb`
- `app/controllers/oauth/registrations_controller.rb`
- `app/controllers/oauth_metadata_controller.rb`
- `app/controllers/omniauth_callbacks_controller.rb`
- `app/controllers/pages_controller.rb`
- `app/controllers/project_invitations_controller.rb`
- `app/controllers/project_memberships_controller.rb`
- `app/controllers/projects_controller.rb`
- `app/controllers/screenshots_controller.rb`
- `app/controllers/static_pages_controller.rb`
- `app/controllers/stripe_webhooks_controller.rb`
- `app/controllers/subscriptions_controller.rb`
- `cmd/screenote/main.go`
- `internal/cli/`
- `internal/screenote/`
- `config/routes.rb`
- `bin/brakeman`
- `bin/bundler-audit`
