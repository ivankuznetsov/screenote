---
title: Web Controllers
type: controller
source: app/controllers/
created: 2026-04-10
updated: 2026-07-28
tags: [controller, web, ui, auth]
---

# Web Controllers

TLDR: 14 web controllers handling the browser-based UI. All inherit from ApplicationController which requires authentication, handles pending invitations, and preloads subscriptions. Project-scoped controllers use the ProjectAuthorization concern.

Source: `app/controllers/`

## ApplicationController

Source: `app/controllers/application_controller.rb`

Base class for all web controllers. Includes:
- `RailsSimpleAuth::Controllers::Concerns::Authentication`
- `RailsSimpleAuth::Controllers::Concerns::SessionManagement`

**before_actions:**
- `require_authentication` -- Redirects to sign-in if not authenticated
- `handle_pending_invitation` -- Checks for invitation token stored in session (from pre-auth invite link click) and auto-accepts it
- `preload_subscription` -- Eagerly loads subscription to avoid N+1 in views

**Rescue handlers:**
- `ActiveRecord::RecordNotFound` -> custom 404 page

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
| show | Member | Shows pages with version counts; each card opens the canonical page workspace at its exact selected version |
| new/create | Member + quota | Checks `can_create_project?` (Free: 1 project limit) |
| edit/update | Owner | |
| destroy | Owner | |

Both overview actions preload `ScreenshotImage` attachments, blobs, tracked
variant records, and their attached output blobs. Rendering a project card or
page card therefore stays on loaded associations and only emits representation
URLs; image processing remains in `ScreenshotThumbnailJob`.

---

## PagesController

Source: `app/controllers/pages_controller.rb`

**Actions:** show, new, create, edit, update, destroy

- `new/create` -- Scoped to project via `params[:project_id]`
- `show` -- Canonical screenshot review workspace for a logical page. It selects
  the newest version by `created_at, id` unless a page-scoped `version_id` is
  supplied, preserves viewport when available, and lists older versions in a
  text-only sidebar.
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
- `create` -- Saves API key, flashes `raw_token` for one-time display
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

- `index` -- Any project member can view
- `destroy` -- Owner only. Cannot remove self.

---

## InvitationAcceptancesController

Source: `app/controllers/invitation_acceptances_controller.rb`

**Actions:** show, create

- **Public** (skips `require_authentication`)
- `show` -- Displays invitation acceptance page
- `create` -- Handles 3 cases: (1) existing user already signed in, (2) existing user not signed in (stores token in session, redirects to login), (3) new user (auto-creates account with random password + confirmed)
- Rescues `MemberLimitExceeded`, `RecordInvalid`, `RecordNotUnique`

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

- `show` -- Displays billing page with subscription state
- `checkout` -- Creates Stripe customer if needed, redirects to Stripe Checkout
- `portal` -- Redirects to Stripe Billing Portal
- Rescues `Stripe::StripeError` with user-friendly message

---

## StripeWebhooksController

Source: `app/controllers/stripe_webhooks_controller.rb`

**Inherits from:** `ActionController::Base` (not ApplicationController -- no auth)

**Actions:** create

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
- `landing` -- Redirects authenticated users to dashboard
- `help` -- Renders static CLI installation, authentication, project setup, snapshot publishing, and command-reference documentation; it no longer enumerates `ApplicationTool.descendants`

---

## OmniauthCallbacksController

Source: `app/controllers/omniauth_callbacks_controller.rb`

**Inherits from:** `RailsSimpleAuth::OmniauthCallbacksController`

**Actions:** create

- Handles OAuth callback from Google/GitHub
- Finds or creates user via `User.from_oauth`
- Creates session and redirects

---

## Admin::DashboardController

Source: `app/controllers/admin/dashboard_controller.rb`

**Actions:** show

- Requires `Current.user.admin?`
- Shows: verified users count, users with projects+screenshots, active Pro users count

---

## OauthMetadataController

Source: `app/controllers/oauth_metadata_controller.rb`

**Public** (skips `require_authentication`)

**Actions:** protected_resource, authorization_server

- `protected_resource` -- RFC 9728 metadata for MCP resource server
- `authorization_server` -- RFC 8414 metadata with endpoints, grant types, code challenge methods

See also: [[routes]], [[controllers/api-controllers]], [[controllers/oauth-controllers]]
