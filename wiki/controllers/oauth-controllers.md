---
title: OAuth Controllers
type: controller
source: app/controllers/oauth/
created: 2026-04-10
updated: 2026-07-09
tags: [controller, oauth, mcp, doorkeeper]
---

# OAuth Controllers

TLDR: OAuth 2.1 provider endpoints for MCP client authentication. Includes custom authorization view, dynamic client registration (RFC 7591), and metadata endpoints (RFC 8414, RFC 9728).

Source: `app/controllers/oauth/`

## Oauth::AuthorizationsController

Source: `app/controllers/oauth/authorizations_controller.rb`

**Inherits from:** `Doorkeeper::AuthorizationsController`

- Uses `auth` layout for the consent screen (consistent with other auth pages)
- Standard Doorkeeper authorization flow with PKCE support

---

## Oauth::RegistrationsController

Source: `app/controllers/oauth/registrations_controller.rb`

**Inherits from:** `ActionController::API` (no session auth)

**Actions:** create

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| create | POST | `/oauth/register` | Dynamic Client Registration (RFC 7591) |

- **Rate limited:** 10 requests per hour per IP
- Validates: redirect_uris required (array), max 10 URIs, client_name max 255 chars
- **Localhost only:** All redirect URIs must point to localhost/127.0.0.1/::1
- Creates Doorkeeper::Application with `confidential: false`, `dynamic: true`
- Scopes: `mcp_read mcp_write`
- Returns: `client_id`, `client_name`, `redirect_uris`, `grant_types`, `token_endpoint_auth_method`

---

## Oauth::TestTokensController

Source: `app/controllers/oauth/test_tokens_controller.rb`

**Inherits from:** `ActionController::API` (no session auth)

**Actions:** create

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| create | POST | `/oauth/test_token` | Secret-gated non-interactive MCP test token minting |

- Gated by `ENV["SCREENOTE_MCP_TEST_TOKEN_SECRET"]`; unset, blank, missing, or mismatched secrets return 404.
- Accepts the secret as `Authorization: Bearer <secret>` or `secret` param.
- Creates or reuses the fixed user `hive-mcp-ci@screenote.test`, fixed project `hive-mcp-ci`, and fixed OAuth application `hive-mcp-ci-test-client`.
- Mints `mcp_read mcp_write` access tokens with `oauth_access_tokens.project_id` set to the fixed test project.
- Project-scoped test tokens resolve `Current.mcp_project` during MCP auth, list only the fixed project, cannot create projects, and cannot use another project even if the fixed test user later gains other memberships.

---

## OauthMetadataController

Source: `app/controllers/oauth_metadata_controller.rb`

**Inherits from:** `ApplicationController` (with `skip_before_action :require_authentication`)

**Actions:** protected_resource, authorization_server

| Action | Method | Path | RFC |
|--------|--------|------|-----|
| protected_resource | GET | `/.well-known/oauth-protected-resource` | RFC 9728 |
| authorization_server | GET | `/.well-known/oauth-authorization-server` | RFC 8414 |

**Protected Resource metadata:**
- `resource`: MCP endpoint URL
- `authorization_servers`: [base URL]
- `bearer_methods_supported`: ["header"]
- `scopes_supported`: ["mcp_read", "mcp_write"]

**Authorization Server metadata:**
- `authorization_endpoint`, `token_endpoint`, `registration_endpoint`, `revocation_endpoint`
- `response_types_supported`: ["code"]
- `grant_types_supported`: ["authorization_code", "refresh_token"]
- `code_challenge_methods_supported`: ["S256"] (PKCE)
- `token_endpoint_auth_methods_supported`: ["none", "client_secret_post"]

## OAuth Flow for MCP Clients

1. Client discovers server metadata via `/.well-known/oauth-authorization-server`
2. Client registers dynamically via `POST /oauth/register`
3. Client redirects user to `/oauth/authorize` with PKCE challenge
4. User authenticates (if needed) and consents
5. Client exchanges authorization code for token at `/oauth/token`
6. Client uses bearer token for MCP requests

See also: [[routes]], [[decisions]] (ADR-007), [[architecture]]
