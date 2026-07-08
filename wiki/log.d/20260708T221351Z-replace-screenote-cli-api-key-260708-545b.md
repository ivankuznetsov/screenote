---
timestamp: 2026-07-08T22:13:51Z
slug: replace-screenote-cli-api-key-260708-545b
---

## [2026-07-08T22:13:51Z] replace-screenote-cli-api-key-260708-545b

**Action:** Refreshed API command/surface wiki coverage after `replace-screenote-cli-api-key-260708-545b`.
**Pages updated:** `wiki/architecture.md`, `wiki/decisions.md`, `wiki/controllers/api-controllers.md`, `wiki/routes.md`, `wiki/api-cli.md`, `wiki/models/api-key.md`, `wiki/gaps.md`
**Pages created:** none
**Source:** committed diff and source for `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/projects_controller.rb`, `app/serializers/api/v1/contract_serializer.rb`, related API controllers, `config/routes.rb`, and API controller tests.
**Notes:** Documented REST `Api::V1` bearer auth as accepting both project API keys and scoped OAuth tokens; documented OAuth project listing screenshot-count precomputation; documented the forbidden JSON guard for stale/projectless API keys.
