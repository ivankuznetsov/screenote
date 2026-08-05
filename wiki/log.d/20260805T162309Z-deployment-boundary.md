## [2026-08-05] Deployment and provider boundary

**Action:** Implemented and reviewed the production configuration boundary shared by SaaS and the first self-hosted runtime.

**Decision:** Production requires an explicit edition, canonical origin, strong application secret, and mode-specific providers. Forwarded identity is honored only from configured immediate proxies; generated URLs and OAuth use the canonical origin. Optional self-hosted providers are inert unless explicitly and completely selected, S3 object keys use the persisted namespace prefix, rate limiting fails closed, and self-hosted monitoring exports only an error class plus opaque identifiers. A singleton `Installation` row persists edition, storage namespace, and bootstrap ownership state and is verified by the supported startup path.

**Pages updated:** `wiki/self-hosting.md`, `wiki/data-model.md`, `wiki/schema-evolution.md`, `wiki/models/user.md`, `wiki/controllers/web-controllers.md`

**Source:** `lib/screenote/deployment.rb`, `app/models/installation.rb`, `app/services/installations/prepare.rb`
