## [2026-07-08T19:42:13Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed command, REST API controller, route, MCP/CLI boundary, and CLI wiki coverage after the `add-a-go-cli-for-260708-edec` branch updated wiki-facing command/API surface documentation.
**Pages updated:** `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`
**Pages already current:** `wiki/api-cli.md`, `wiki/index.md`, `wiki/gaps.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `config/routes.rb`, `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/*`, `app/serializers/api/v1/contract_serializer.rb`, `app/services/api/v1/project_scope.rb`, `cmd/screenote`, `internal/cli`, and `internal/screenote`.
**Notes:** Kept wiki edits in the main checkout only. Used `qmd search` and source inspection; did not run `qmd update` or `qmd embed`.
