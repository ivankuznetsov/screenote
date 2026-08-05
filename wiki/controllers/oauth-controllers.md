---
title: OAuth Controllers
type: controller
source: app/controllers/oauth/
created: 2026-04-10
updated: 2026-08-05
tags: [controller, oauth, cli, doorkeeper]
---

# OAuth Controllers

TLDR: OAuth provider endpoints for browser and headless CLI authentication. Includes PKCE authorization code, RFC 8628 device authorization, dynamic client registration, and metadata endpoints.

Source: `app/controllers/oauth/`

## Oauth::AuthorizationsController

Source: `app/controllers/oauth/authorizations_controller.rb`

**Inherits from:** `Doorkeeper::AuthorizationsController`

- Uses `auth` layout for the consent screen and Doorkeeper's PKCE flow.
- Ignores client-supplied principal fields. The signed-in user explicitly chooses account-wide authority or one project from a server-derived membership list.
- Persists `principal_kind` and `project_id` on the authorization grant; a foreign or stale project choice creates no grant.
- Project consent holds the resource-owner, project, and membership authority locks through authorization-code creation, so concurrent membership removal cannot race the final grant write.
- Consent is never skipped because the authority choice must remain visible.
- A user may hold active credentials for at most 25 distinct dynamically registered clients. The user lock serializes consent, reauthorization of an already-counted client remains available, and revoked or expired credentials release capacity.

## Oauth::TokensController

Source: `app/controllers/oauth/tokens_controller.rb`

**Inherits from:** `Doorkeeper::TokensController`

- Rejects authorization-code and refresh exchanges when their project membership is no longer held.
- Code and refresh exchange use the same user -> project -> membership -> source-credential lock order and keep those locks through replacement-token creation.
- Doorkeeper propagates the server-owned principal fields from grant to token and through refresh rotation.
- Access codes, access tokens, refresh tokens, previous refresh tokens, and confidential client secrets are SHA-256 digests at rest with no plaintext fallback.

---

## Oauth::RegistrationsController

Source: `app/controllers/oauth/registrations_controller.rb`

**Inherits from:** `ActionController::API` (no session auth)

**Actions:** create

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| create | POST | `/oauth/register` | Dynamic Client Registration (RFC 7591) |

- **Rate limited:** 10 requests per hour per trusted request IP; a counter outage fails closed with 503.
- Accepts the RFC 7591 top-level JSON object without Rails model-style parameter wrapping; blank names default to `OAuth Client`.
- Validates: redirect_uris required (array), max 10 URIs, client_name max 255 chars
- **Exact native loopback only:** Redirects must use HTTP with the literal `127.0.0.1` or `[::1]`, without credentials, fragments, controls, encoded-host ambiguity, or duplicates.
- Creates Doorkeeper::Application with `confidential: false`, `dynamic: true`
- Scopes: `mcp_read mcp_write`
- Returns additive authorization-code, device-code, and refresh-token grant metadata with the client details
- Identical registrations deduplicate under a unique fingerprint. A process lock plus the singleton Installation lock makes the 10,000-client global capacity check deterministic; stale clients without active grants/tokens/device codes are cleaned hourly.
- Available in SaaS and only after a self-hosted Installation is claimed. Pre-claim registration returns 404 and metadata omits the registration endpoint.

---

## Oauth::DeviceAuthorizationRequestsController

Source: `app/controllers/oauth/device_authorization_requests_controller.rb`

**Inherits from:** `ActionController::API` (no session auth)

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| create | POST | `/oauth/authorize_device` | Starts an RFC 8628 authorization request for a public client |

- Accepts public clients only and validates requested scopes against the client and server scope sets.
- Returns a 10-minute device code, a 5-second initial polling interval, a human code, and verification URLs with `Cache-Control: no-store`.
- Stores only the SHA-256 device-code digest. Human codes contain 50 bits of entropy, remain plaintext for lookup, and are protected by short expiry and verification throttling.
- Limits initiation per source IP and returns `temporarily_unavailable` with `Retry-After` when exceeded.

## Oauth::DeviceAuthorizationsController

Source: `app/controllers/oauth/device_authorizations_controller.rb`

**Inherits from:** `ApplicationController` (session authentication and CSRF protection)

| Action | Method | Path | Notes |
|--------|--------|------|-------|
| show | GET | `/oauth/device` | Enter or review a one-time user code |
| update | POST | `/oauth/device` | Explicitly approve or deny the displayed client, code, and scopes |

- A complete verification URL only pre-fills the code; it never approves silently.
- The consent page shows client identity, exact user code, and requested scopes with separate Approve and Deny controls.
- Every submitted GET or POST code consumes a shared per-user/IP verification budget before lookup; an unavailable counter fails closed with a retryable 503. Device and user codes are filtered from Rails logs.
- Approval binds the grant either to the signed-in user's account or to one server-validated current project membership. Final polling revalidates that binding, issues one refreshable token with the same authority, and atomically consumes the grant.
- Project approval and final exchange hold authority locks through the device-grant update or token write. PostgreSQL uses row locks; SQLite begins with a serialized no-op user write because it ignores `FOR UPDATE`.
- Device approval uses the same 25-active-dynamic-client quota as browser authorization-code consent and leaves the device grant pending when the quota is full.
- Polling returns RFC 8628 `authorization_pending`, `slow_down`, `access_denied`, and `expired_token`; unknown, reused, or wrong-client codes return `invalid_grant`.

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
- Project-scoped test tokens resolve one immutable `Current.authenticated_principal` during MCP auth, list only the fixed project, cannot create projects, and cannot use another project even if the fixed test user later gains other memberships.

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
- `authorization_endpoint`, `device_authorization_endpoint`, `token_endpoint`, and `revocation_endpoint`; `registration_endpoint` appears only when DCR is available
- `response_types_supported`: ["code"]
- `grant_types_supported`: ["authorization_code", "urn:ietf:params:oauth:grant-type:device_code", "refresh_token"]
- `code_challenge_methods_supported`: ["S256"] (PKCE)
- `token_endpoint_auth_methods_supported`: ["none", "client_secret_post"]

## OAuth Flows

1. Client discovers server metadata via `/.well-known/oauth-authorization-server`
2. Client registers dynamically via `POST /oauth/register`
3. Client redirects user to `/oauth/authorize` with PKCE challenge
4. User authenticates (if needed) and consents
5. Client exchanges authorization code for token at `/oauth/token`
6. Client uses bearer token for MCP requests

The CLI uses the same authorization-code flow by default. `screenote login --device` instead starts `/oauth/authorize_device`, displays the verification link/code, and polls `/oauth/token` with the exact RFC 8628 grant URN until the user explicitly approves or denies it.

See also: [[routes]], [[decisions]] (ADR-007), [[architecture]]
