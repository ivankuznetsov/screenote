---
title: Web Controllers
type: controller
source: app/controllers/
created: 2026-04-10
updated: 2026-08-13
tags: [controller, web, ui, auth]
---

# Web Controllers

TLDR: Browser controllers share app-owned authentication and project authorization. Subscription preload and hosted commercial controllers exist only behind the SaaS billing capability; self-hosted instance administration is a distinct, installation-bound authority.

Source: `app/controllers/`

## ApplicationController

Source: `app/controllers/application_controller.rb`

Base class for all web controllers. Includes:
- `RailsSimpleAuth::Controllers::Concerns::Authentication`
- `ScreenoteSessionManagement`
- `PageWorkspaceNavigation`

**before_actions:**
- `require_authentication` -- Redirects to sign-in if not authenticated
- `preload_subscription` -- Eagerly loads subscriptions only when the deployment enables SaaS billing; self-hosted requests never make this query

`ScreenoteSessionManagement` serializes every durable session insert with the
resource-owner user lock. Successful password, OAuth, magic-link, invitation,
registration, bootstrap, and recovery flows use one replacement primitive: a
valid same-account session is retained, while switching identities destroys the
previous database session before issuing the new credential.

Login, registration, confirmation, magic-link, password-reset, exchanged-link,
bootstrap, and recovery endpoints all use lazy `Screenote::RateLimitStore`
wrappers around the configured controller cache. Backend failure returns a
private retryable response instead of disabling throttling; tests and in-process
browser runs install a fresh isolated controller `MemoryStore` per case.

Password login delegates lookup and password work to Active Record's
timing-safe `authenticate_by`, then applies the shared active-account predicate.
Missing, suspended, and active identities therefore all cross a comparable
password-digest boundary before access status can affect the response.

**Rescue handlers:**
- `ActiveRecord::RecordNotFound` -> custom 404 page

## StaticPagesController

The public help and landing pages lead with tagged CLI binaries instead of a
Go source install. Hosted first run is `curl -fsSL
https://screenote.ai/install.sh | sh` followed by `screenote login`; macOS also
shows the Homebrew tap. `GET /install.sh` returns the reviewed POSIX installer
with a short public cache lifetime. The installer selects macOS/Linux and
AMD64/ARM64 assets, verifies the release archive against `checksums.txt`, then
installs `screenote`. Self-hosted help retains an explicit `--base-url` login
command for its own canonical origin.

---

## ProjectAuthorization (Concern)

Source: `app/controllers/concerns/project_authorization.rb`

Shared by controllers that need project-level access control.

- `set_project` -- Finds project via `Current.user.projects.find(...)` (scoped through memberships)
- `require_owner!` -- Redirects if current user is not a project owner

**Used by:** ProjectsController, ApiKeysController, ProjectInvitationsController, ProjectMembershipsController, CollaboratorSuggestionsController

---

## ProjectsController

Source: `app/controllers/projects_controller.rb`

**Actions:** index, show, new, create, edit, update, destroy

| Action | Auth | Notes |
|--------|------|-------|
| index | Member | Lists user's projects ordered by updated_at with up to four prewarmed `project_strip` thumbnails |
| show | Member | Shows pages with version counts; optional `path_prefix` limits cards to one route and its descendants; each card opens the canonical page workspace at its exact selected version |
| new/create | Member + edition policy | Uses `Projects::Create`; SaaS keeps the plan quota while self-hosted creation is unlimited |
| edit/update | Owner | |
| destroy | Owner | |

Both overview actions preload `ScreenshotImage` attachments, blobs, tracked
variant records, and their attached output blobs. Project show applies any path
filter before preloading page-card thumbnails, so filtered-out pages do not load
image records. Rendering a project card or page card therefore stays on loaded
associations and only emits representation URLs; image processing remains in
`ScreenshotThumbnailJob`.

Browser creation uses the same authenticated-principal operation as REST and
MCP. The user row lock serializes quota evaluation with insertion; only a
billing-enabled SaaS deployment applies the free-plan limit.

---

## PagesController

Source: `app/controllers/pages_controller.rb`

**Actions:** show, new, create, edit, update, destroy

- `new/create` -- Scoped to project via `params[:project_id]`
- `show` -- Canonical screenshot review workspace for a logical page. It selects
  the newest version by `created_at, id` unless a page-scoped `version_id` is
  supplied, preserves viewport when available, lists older versions in a
  text-only sidebar, and loads the user's accessible projects for the header
  switcher.
- `edit/update/destroy` -- Finds page by ID, verifies project membership

---

## ScreenshotsController

Source: `app/controllers/screenshots_controller.rb`

**Actions:** show, new, create, edit, update, destroy

- `new/create` -- Scoped to page via `params[:page_id]`
- `show` -- Compatibility endpoint that redirects to the owning page workspace
  with the screenshot encoded as `version_id`.
- `viewports/:viewport` -- Compatibility endpoint that redirects to the same
  page workspace while preserving the constrained desktop/tablet/mobile viewport.
- `destroy` -- Deletes one version under the owning page lock. A remaining
  version becomes the selected page workspace; deleting the final version also
  deletes the empty page and returns to the project overview.
- Permits: `title`, `image`

The review layout and Annotorious interaction rules are documented in [[frontend-review-ui]].

---

## AnnotationsController

Source: `app/controllers/annotations_controller.rb`

**Actions:** create, update, destroy

- All actions scoped via screenshot -> project membership check
- `create` -- Builds annotation, assigns `Current.user`
- `update` -- Handles two paths: (1) resolve if `status=resolved`, (2) standard attribute update
- Permits: `x_percent`, `y_percent`, `width_percent`, `height_percent`, `comment`, `viewport`
- A submitted viewport must exist on the selected screenshot. Blank viewport
  input is ignored so create retains the model default and update retains the
  annotation's persisted viewport.

---

## AnnotationCommentsController

Source: `app/controllers/annotation_comments_controller.rb`

**Actions:** create

- Handles two paths: (1) reopen annotation if `reopen=1`, (2) regular comment
- Scoped via screenshot -> annotation -> project membership check
- Permits: `body`, `reopen`

---

## ApiKeysController

Source: `app/controllers/api_keys_controller.rb`

**Actions:** index, new, create, destroy

- All actions require project **owner** role
- `create` -- Rechecks owner authority under the shared user/project/membership locks, saves the API key before releasing those locks, and flashes `raw_token` for one-time display
- `destroy` -- Soft-deletes by calling `revoke!`

---

## ProjectInvitationsController

Source: `app/controllers/project_invitations_controller.rb`

**Actions:** create, destroy

- Requires project **owner** role
- `create` -- Checks member limit, sends invitation email via `ProjectInvitationMailer`
- `destroy` -- Only allows cancelling pending invitations

---

## ProjectMembershipsController

Source: `app/controllers/project_memberships_controller.rb`

**Actions:** index, destroy

- `index` -- Any project member can view. Owner-only re-presented invitation credentials are delivered under `no-store`/no-referrer headers and wrapped in `data-turbo-temporary`, so Turbo removes them before caching a page snapshot.
- `destroy` -- Delegates to the same serialized membership-removal operation as MCP. It rechecks owner authority, cannot remove self, and revokes the removed member's project-bound credentials atomically.

---

## InvitationAcceptancesController

Source: `app/controllers/invitation_acceptances_controller.rb`

**Actions:** show, create

- **Public** (skips `require_authentication`)
- `show` -- Revalidates the token-ID-only exchange context and offers proof appropriate to the invited identity
- `create` -- Delegates locked acceptance to `ProjectInvitations::Accept`; local proof either verifies an existing password or creates explicit local credentials for a new invitee
- Retryable local validation has a distinct `invalid_input` result that retains the tokenless invitation context, project details, and labelled password form; terminal token states still clear the context
- A successful cross-account acceptance destroys the former permanent browser-session row before creating the invited user's session, so the old cookie cannot be replayed

---

## CollaboratorSuggestionsController

Source: `app/controllers/collaborator_suggestions_controller.rb`

**Actions:** index

- Owner only, rate-limited (30/min)
- Returns autocomplete suggestions from users in other shared projects
- Excludes current members, pending invites, and self
- Requires minimum 2-character query

---

## SubscriptionsController

Source: `app/controllers/subscriptions_controller.rb`

**Actions:** show, checkout, portal

- SaaS-only: its routes are not drawn without the billing capability, and the controller independently returns not-found if reached after capability drift

- `show` -- Displays billing page with subscription state
- `checkout` -- Creates Stripe customer if needed, redirects to Stripe Checkout
- `portal` -- Redirects to Stripe Billing Portal
- Rescues `Stripe::StripeError` with user-friendly message

---

## StripeWebhooksController

Source: `app/controllers/stripe_webhooks_controller.rb`

**Inherits from:** `ActionController::Base` (not ApplicationController -- no auth)

**Actions:** create

- SaaS-only: the webhook route is absent without billing and the controller rejects a drifted self-hosted dispatch before reading or verifying a Stripe payload

- Verifies Stripe webhook signature
- Handles: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`
- Inserts `StripeWebhookEvent` before dispatch so duplicate Stripe retries do not re-run side effects
- Sends admin notification email on new Pro subscriber
- Reports errors to Honeybadger
- `current_period_end` is read from `items.data[0]` (Stripe API 2026-01-28 moved it off `Subscription` onto each `SubscriptionItem`); uses hash-style access so a missing key returns `nil` rather than raising via `StripeObject#method_missing`
- `handle_subscription_updated` / `handle_subscription_deleted` no-op when the incoming Stripe sub ID doesn't match the tracked `stripe_subscription_id`, so events from a second (duplicate) Stripe subscription can't corrupt or wipe the active one

---

## StaticPagesController

Source: `app/controllers/static_pages_controller.rb`

**Actions:** landing, help, terms, privacy

- **Public** (skips `require_authentication`)
- `landing` -- SaaS root; redirects authenticated users to dashboard
- `help` -- Renders static CLI installation, authentication, project setup, snapshot publishing, and command-reference documentation; it no longer enumerates `ApplicationTool.descendants`
- `terms` / `privacy` -- Hosted-service legal pages; routes are absent and direct dispatch returns not-found in self-hosted mode

---

## OmniauthCallbacksController

Source: `app/controllers/omniauth_callbacks_controller.rb`

**Actions:** create

- Handles only explicitly enabled Google/GitHub callbacks with verified email evidence
- SaaS may create a collision-free account; self-hosted OAuth never bypasses bootstrap/invitation admission
- App-owned session issuance rejects inactive accounts
- OmniAuth request phase accepts POST only and uses Rack Protection bound explicitly to Rails' encrypted-session `:_csrf_token`; real Rails-generated form tokens reach the provider, while missing or invalid tokens fail before provider redirect. OAuth2 callback state remains a separate check.
- Invitation acceptance requires the current OmniAuth request's exact local `origin` intent marker as well as token-ID-only invitation context. Normal sign-in and registration forms emit their own non-invitation local origin, which overwrites an abandoned request marker; ordinary OAuth clears stale invitation context instead of accepting it.

---

## AuthenticationLinksController

Source: `app/controllers/authentication_links_controller.rb`

**Actions:** show, exchange

- The sterile page scrubs fragment credentials before sending them in a same-origin POST and never persists the raw value in cookies, storage, or markup.
- Terminal invalid responses discard the in-memory credential. HTTP 429, transient database 503, and network failures expose a retry action that retains it only in the connected Stimulus controller; disconnecting clears it.
- Exchange responses are private and non-cacheable. Resolver database failures return `503 Service Unavailable` with `Retry-After` instead of becoming a terminal-invalid message.

---

## Admin::DashboardController

Source: `app/controllers/admin/dashboard_controller.rb`

**Actions:** show

- SaaS-only route guarded by `Current.user.saas_operator?`; self-hosted instance administrators receive no hosted dashboard privilege
- Shows: verified users count, users with projects+screenshots, active Pro users count

---

## OauthMetadataController

Source: `app/controllers/oauth_metadata_controller.rb`

**Public** (skips `require_authentication`)

**Actions:** protected_resource, authorization_server

- `protected_resource` -- RFC 9728 metadata for MCP resource server
- `authorization_server` -- RFC 8414 metadata with endpoints, grant types, code challenge methods

See also: [[routes]], [[controllers/api-controllers]], [[controllers/oauth-controllers]]
