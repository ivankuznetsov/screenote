## [2026-08-30] Make the image attachment release claims executable

**Action:** Four release claims for image attachments could only be verified by
reading a diff, so each one gained a way to run. The lifecycle suites moved from
a list embedded in one CI workflow into
`script/release_test_matrix attachment-lifecycle`, which runs against whatever
database is configured, and `script/attachment_server_database_qualification`
boots an ephemeral server database and reruns the identical list under real row
locks, so the account byte-ceiling race and the adapter assertion are no longer
reachable only inside GitHub Actions. Attachment delivery gained an object-store
contract that points the whole application at a real S3-compatible service and
drives the protected session and bearer routes through it — provider-stored
bytes, no `Location`, no provider host in any header, application-served byte
ranges, the five-minute purpose token expiring, and revoked membership losing
access — and it runs in the existing `s3` gate. The clamped overlay's
"never covers the selected region" claim is now measured against a full-size
1440x900 page capture instead of a 300px fixture, where zero overlap is a real
guarantee rather than an impossibility. Browser runs can record themselves:
`SCREENOTE_EVIDENCE_DIR` writes a Playwright trace per test plus named frames
carrying the resolved media paths, srcset candidates, component context, and
measured geometry, and `script/attachment_browser_evidence` extracts each trace
into an ordered filmstrip. The gallery's neutral placeholder and its warmed
responsive thumbnails are now both asserted, as is the composer's polite live
region and the viewer's full control set. Pinning the Go toolchain lets the CLI
contract tests run outside CI.

**Pages updated:** wiki/testing-and-ci.md, wiki/gaps.md,
wiki/log.d/20260830T170000Z-image-attachment-executed-evidence.md

**Source:** `script/release_test_matrix`,
`script/attachment_server_database_qualification`,
`script/attachment_browser_evidence`,
`.github/workflows/concurrency-qualification.yml`,
`test/integration/image_attachment_s3_delivery_contract_test.rb`,
`test/support/s3_contract_helper.rb`,
`test/system/application_system_test_case.rb`,
`test/system/image_attachments_test.rb`, and
`test/fixtures/files/desktop_screenshot.png`
