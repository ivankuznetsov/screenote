# MCP principal and registry hardening

- Replaced the mutable MCP user/project/key/token tuple with one immutable `AuthenticatedPrincipal` in request-local state.
- Required exact orthogonal `mcp_read` or `mcp_write` authorization and complete safety metadata on every remotely registered tool.
- Replaced subclass discovery with an explicit 18-tool allowlist that excludes bootstrap, account-administration, recovery, transfer, publication, and secret-management actions.
- Preserved API-key project authority without impersonating the issuer and attributed supported annotation mutations to the key.
- Added request-reset, registry, scope, project-boundary, person-only-action, and API-key actor regression coverage.

Source: `app/models/current.rb`, `config/initializers/fast_mcp.rb`, `app/tools/**/*.rb`, `test/tools/mcp_security_contract_test.rb`
