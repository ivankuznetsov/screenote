## [2026-07-08T15:34:48Z] refresh

**Action:** Refreshed project wiki against current LLM-wiki automation and recent git history.
**Pages created:** `wiki/llm-wiki-maintenance.md`
**Pages updated:** `wiki/index.md`, `wiki/gaps.md`
**Pages unchanged after source verification:** core architecture/model/controller/MCP pages; recent commits after the prior refresh changed LLM-wiki automation and context files, not application source behavior.
**Cross-project wiki:** `.llm-wiki/config.json` still points at `/home/asterio/wikis/master/wiki`, but that path and the default fallback main wiki paths were absent on this machine during refresh.
**QMD:** Used `qmd search` only; did not run `qmd update` or `qmd embed`.
**Source:** `.llm-wiki/config.json`, `AGENTS.md`, `CLAUDE.md`, `.llm-wiki/refresh-wiki.sh`, `.llm-wiki/post-commit-refresh.sh`, `.llm-wiki/compile-log.sh`, `.claude/settings.json`, recent `git log`, source inventory under `app/`, `config/`, `db/`, `plans/`, and `todos/`.
