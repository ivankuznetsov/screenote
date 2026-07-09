## [2026-07-08T19:14:11Z] add-a-go-cli-for-260708-edec

**Action:** Refreshed main-checkout wiki coverage after the `add-a-go-cli-for-260708-edec` residual 6-review commit changed only branch-local wiki files while the committed CLI/API source tree still supports the richer documented command and REST API surface.
**Pages updated:** `wiki/gaps.md`
**Pages verified current:** `wiki/api-cli.md`, `wiki/commands.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/mcp-tools.md`, `wiki/index.md`, `wiki/llm-wiki-maintenance.md`
**Source:** `git show add-a-go-cli-for-260708-edec`, `README.md`, `cmd/screenote/main.go`, `internal/cli/annotation.go`, `internal/cli/screenshot.go`, `internal/cli/root.go`, `internal/cli/errors.go`, `internal/screenote/client.go`, `internal/screenote/types.go`, `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/*`, `app/serializers/api/v1/contract_serializer.rb`, and `config/routes.rb`.
**Uncertainty:** `qmd search` returned no matching results for the CLI/API refresh query, and the configured cross-project wiki path remained unavailable. The branch-local wiki maintenance/log rollback conflicts with the main-checkout wrapper instruction to add fragments and avoid direct compiled `wiki/log.md` edits.
**Notes:** Kept edits in `/home/asterio/Dev/screenote/wiki/` only. Did not run `qmd update` or `qmd embed`; did not edit compiled `wiki/log.md`.
