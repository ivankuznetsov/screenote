# Help Page Redesign: Public Access, Claude Code Workflow, MCP Documentation

## Overview

The help page is currently behind authentication and has thin content. This plan makes it fully public, expands the Claude Code quick start, and adds MCP connection documentation for developers integrating other agents.

## Problem Statement

1. **Help is gated** — only authenticated users can see setup docs, so potential users evaluating Screenote can't learn how it works
2. **Claude Code workflow is too brief** — three numbered steps don't convey the power of the feedback loop
3. **MCP section lacks connection info** — lists tool names/params but no endpoints, auth methods, or integration guide for non-Claude-Code agents
4. **No path from landing to help** — the landing page has no Help link anywhere

## Proposed Changes

### 1. Make Help Page Public

**Controller** (`app/controllers/pages_controller.rb`):
- Blanket `skip_before_action :require_authentication` — PagesController serves public pages; if you need auth, use a different controller

```ruby
class PagesController < ApplicationController
  skip_before_action :require_authentication

  layout "landing", only: [ :landing ]

  def landing
    redirect_to dashboard_path if Current.user
  end

  def help
    @tools = ApplicationTool.descendants.sort_by(&:tool_name)
  end

  def terms; end
  def privacy; end
end
```

No route changes required — `get "help", to: "pages#help"` already exists.

**Application layout nav** (`app/views/layouts/application.html.erb`):
- Add an `else` branch so unauthenticated visitors see `Help | Sign In | Get Started` instead of an empty nav
- Fix the logo link: point to `root_path` for guests (landing) vs `dashboard_path` for authenticated users
- This also fixes the same broken-nav issue for `/terms` and `/privacy` (which are already public but have no guest nav)

```erb
<div class="header__logo">
  <%= link_to (Current.user ? dashboard_path : root_path), class: "header__title" do %>
    <%= render "shared/logo_icon" %>
    Screenote
  <% end %>
</div>
<nav class="header__nav">
  <% if Current.user %>
    <%= link_to "Help", help_path, class: "header__link" %>
    <%= link_to "Billing", subscription_path, class: "header__link", data: { testid: "billing-link" } %>
    <% if Current.user.admin? %>
      <%= link_to "Admin", admin_dashboard_path, class: "header__link" %>
    <% end %>
    <span class="header__email" data-testid="user-email"><%= Current.user.email %></span>
    <%= button_to "Sign out", session_path, method: :delete, class: "header__sign-out", data: { testid: "sign-out-button" } %>
  <% else %>
    <%= link_to "Help", help_path, class: "header__link" %>
    <%= link_to "Sign In", new_session_path, class: "header__link" %>
    <%= link_to "Get Started", sign_up_path, class: "header__link header__link--cta" %>
  <% end %>
</nav>
```

**Landing page** (`app/views/pages/landing.html.erb`):
- Add Help link to the landing footer alongside Terms and Privacy
- Keep the top nav conversion-focused (Sign In / Get Started only)

```erb
<nav class="landing-footer__links">
  <%= link_to "Help", help_path %>
  <%= link_to "Terms", terms_path %>
  <%= link_to "Privacy", privacy_path %>
</nav>
```

### 2. Restructure Help Page Content

The page keeps the `application` layout (with the new guest nav) and the existing `guide__*` BEM classes. Split into partials for maintainability:

```
app/views/pages/help.html.erb              # skeleton with section ordering
app/views/pages/_help_quick_start.html.erb  # Claude Code setup + commands
app/views/pages/_help_workflows.html.erb    # Agent Feedback Loop + Capture & Annotate
app/views/pages/_help_mcp.html.erb          # MCP connection docs + tools reference
```

**Main skeleton** (`help.html.erb`):

```erb
<div class="guide">
  <div class="guide__hero">
    <h1 class="guide__title">Getting Started</h1>
    <p class="guide__subtitle">Set up Screenote in Claude Code and start getting visual feedback in under a minute.</p>
  </div>

  <%= render "pages/help_quick_start" %>
  <hr class="guide__divider">
  <%= render "pages/help_workflows" %>
  <hr class="guide__divider">
  <%= render "pages/help_mcp", tools: @tools %>
</div>
```

**Quick Start partial** (`_help_quick_start.html.erb`):
- Keep the existing 3-step structure (Install, Authorize, Use)
- Fix command syntax: `/screenote <url>` instead of `/screenote login`
- Expand step 3 to show the full loop: `/screenote <url>` → annotate → `/screenote feedback`
- Add anchor ID `#quick-start`

**Workflows partial** (`_help_workflows.html.erb`):
- Keep the existing two workflow cards (Agent Feedback Loop + Capture & Annotate)
- Fix command names in the Agent Feedback Loop steps to use correct syntax
- Add anchor ID `#workflows`

**MCP Connection partial** (`_help_mcp.html.erb`) — **new content**:
- Add anchor ID `#mcp`

Content structure:

```
Connecting Other Agents via MCP

  MCP Endpoint
    Your MCP server URL: <%= root_url %>mcp

  Authentication (two methods)
    OAuth 2.1 (recommended for MCP clients)
      - Discovery: GET /.well-known/oauth-authorization-server
      - Dynamic registration: POST /oauth/register (RFC 7591)
      - Standard OAuth 2.1 with PKCE (public clients)
      - Scopes: mcp_read (default), mcp_write (optional)
      - Access tokens expire in 1 hour, refresh tokens enabled

    API Keys (simple, single-project)
      - Create in project settings → API Keys
      - Use as Bearer token: Authorization: Bearer sk_proj_...
      - Each key is scoped to one project

  Note about project_id:
    - API key auth: project is implicit, project_id parameter is optional
    - OAuth auth: must pass project_id to each tool call

  MCP Tools Reference
    Keep existing dynamic rendering from @tools (flat grid, no grouping)
    Keep parameters inline and visible (no collapsible <details>)
```

### 3. CSS Changes

Minimal additions to `app/assets/stylesheets/application.css`:

- `.header__link--cta` — accent-colored "Get Started" link in guest nav
- `.guide__mcp-*` — styles for the new MCP connection section (endpoint display, auth method blocks)

No new stylesheet files. No changes to existing guide styles.

### 4. Tests

Update `test/controllers/pages_controller_test.rb`:

```ruby
test "help page is publicly accessible" do
  get help_path
  assert_response :success
  assert_select "[data-testid='tool-card']"  # tools render without auth
end

test "unauthenticated help page shows guest nav" do
  get help_path
  assert_select "a", text: "Sign In"
  assert_select "a", text: "Get Started"
end

test "terms page shows guest nav for unauthenticated user" do
  get terms_path
  assert_response :success
  assert_select "a", text: "Sign In"
end

test "landing page footer links to help" do
  get root_path
  assert_select "a[href='#{help_path}']", text: "Help"
end
```

## Acceptance Criteria

- [ ] `/help` returns 200 for unauthenticated visitors
- [ ] Unauthenticated visitors see "Help | Sign In | Get Started" in the nav bar
- [ ] Logo links to landing page for guests, dashboard for authenticated users
- [ ] Guest nav also works on `/terms` and `/privacy`
- [ ] Landing page footer includes a "Help" link
- [ ] Claude Code Quick Start uses correct command syntax (`/screenote <url>`, `/screenote feedback`)
- [ ] MCP section documents the endpoint URL
- [ ] MCP section documents both OAuth 2.1 and API key authentication
- [ ] MCP section explains the `project_id` parameter behavior difference between auth methods
- [ ] Tools reference renders dynamically (flat grid, parameters visible inline)
- [ ] Help page is split into partials (quick_start, workflows, mcp)
- [ ] Existing tests updated and all pass (`bin/rails test`)
- [ ] Rubocop passes (`bin/rubocop`)
- [ ] Brakeman passes (`brakeman -q`)

## Files to Modify

| File | Change |
|------|--------|
| `app/controllers/pages_controller.rb` | Blanket `skip_before_action :require_authentication` |
| `app/views/layouts/application.html.erb` | Add guest nav else branch, fix logo link |
| `app/views/pages/landing.html.erb` | Add Help link to footer |
| `app/views/pages/help.html.erb` | Refactor into skeleton with partials |
| `app/views/pages/_help_quick_start.html.erb` | **New** — extracted quick start section |
| `app/views/pages/_help_workflows.html.erb` | **New** — extracted workflows section |
| `app/views/pages/_help_mcp.html.erb` | **New** — MCP connection docs + tools reference |
| `app/assets/stylesheets/application.css` | `.header__link--cta` + MCP section styles |
| `test/controllers/pages_controller_test.rb` | Update auth test, add guest nav + landing footer tests |

## Dependencies & Risks

- **Test breakage**: The existing test "help page requires authentication" must be updated. No other tests reference the auth requirement for `/help`.
- **Terms/Privacy benefit**: Adding the guest nav `else` branch fixes the same empty-nav problem on `/terms` and `/privacy` for free — now tested.
- **`ApplicationTool.descendants` requires eager loading**: Tools are explicitly required in `config/initializers/fast_mcp.rb` at boot, so this works in all environments. If that require loop is ever removed, the tools section silently empties.
- **OAuth scoping in flux**: Todo #108 notes that OAuth project scoping may be rethought. The MCP docs describe current behavior without over-specifying internals.
- **Dynamic vs static content**: The tools reference stays dynamic (from `ApplicationTool.descendants`). The connection/auth documentation is static prose. This hybrid approach means adding a tool automatically updates the reference section.

## References

- Current help page: `app/views/pages/help.html.erb`
- Current controller: `app/controllers/pages_controller.rb:4`
- Application layout: `app/views/layouts/application.html.erb:17-25`
- Landing page: `app/views/pages/landing.html.erb:134-143`
- MCP config: `config/initializers/fast_mcp.rb`
- OAuth metadata: `app/controllers/oauth_metadata_controller.rb`
- Base tool class: `app/tools/application_tool.rb`
- Auth test: `test/controllers/pages_controller_test.rb:20-24`
- Routes: `config/routes.rb:55` (no changes needed)
