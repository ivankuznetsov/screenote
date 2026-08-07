## [2026-08-07] Make team onboarding the public README path

**Action:** Reframed the repository README around the publish-review-feedback
loop, a clear hosted versus self-hosted choice, and a five-step Docker team
setup covering claim and invitation-based admission. The setup remains
explicitly gated on the first published source tag, image digest, and CLI tag,
so the easier onboarding does not present unpublished artifacts as supported.
Advanced storage, provider, backup, restore, and upgrade operations continue to
route to the canonical operator documentation. The quick start also requires
narrow immediate-proxy trust before HTTPS bootstrap and does not imply that
bare Ruby and Bundler are enough to run the unpublished host-operation tools.

**Pages updated:** README.md, wiki/self-hosting.md,
wiki/log.d/20260807T153517Z-team-onboarding-readme.md

**Source:** README.md, docs/self-hosting.md, compose.yaml,
compose.bootstrap.yaml, .env.self-hosted.example, and current release state
