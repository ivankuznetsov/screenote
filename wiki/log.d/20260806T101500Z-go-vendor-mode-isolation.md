## [2026-08-06] Isolate Go checks from the Rails vendor directory

**Action:** Made the repository Go compatibility step explicitly use module
mode. The Rails/Bundler top-level `vendor/` tree is not a Go dependency vendor
tree, and Go 1.26 otherwise rejects it before compiling repository helpers.

**Pages updated:** wiki/api-cli.md,
wiki/log.d/20260806T101500Z-go-vendor-mode-isolation.md, wiki/log.md

**Source:** `.github/workflows/ci.yml`, `config/ci.rb`, and a reproduced Go 1.26
inconsistent-vendoring failure
