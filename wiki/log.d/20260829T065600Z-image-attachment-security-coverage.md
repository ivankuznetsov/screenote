## [2026-08-29] Declare image attachment security coverage owners

**Action:** Assigned every image-attachment session and API controller, plus
both shared authorization and streaming concerns, to the `principal` domain in
the release security coverage manifest. This keeps controller discovery fail
closed as the feature adds protected draft and media routes.

**Pages updated:** wiki/testing-and-ci.md,
wiki/log.d/20260829T065600Z-image-attachment-security-coverage.md

**Source:** `test/manifests/release_security_coverage.yml`,
`app/controllers/image_attachment_drafts/`,
`app/controllers/image_attachment_media_controller.rb`,
`app/controllers/api/image_attachment_media_controller.rb`, and
`app/controllers/concerns/`
