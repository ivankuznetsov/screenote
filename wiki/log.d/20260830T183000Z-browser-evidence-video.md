## [2026-08-30] Encode the browser evidence run as watchable video

**Action:** A recorded system-test run now leaves a WebM per test beside its
trace and named frames, so the image attachment authoring flow can be watched
rather than reconstructed frame by frame.
`script/attachment_browser_evidence` encodes the video from the Playwright
trace's screencast: it runs at roughly 20 frames a second for the whole length
of a test, and every frame keeps the millisecond it was captured at in its
name, so a concat encode holds each frame for its real gap and replays the run
at its own pace. Playwright's own `record_video_dir` remains unusable —
`capybara-playwright-driver` asks the page for its video path while the page is
still open, and `Playwright::Video#path` blocks on a future the page-close
event rejects, so a run that sets the option hangs and leaves a zero-byte file.
Frame ordering now reads the numeric tail from the bare file name; sorting whole
paths keyed on a hyphen in the enclosing directory instead.

The gallery's narrow-width claim grew to the viewer that opens from it, and the
explicit light and dark component contexts are now captured at a phone-sized
viewport as well as at desktop, so every component context the plan names has
evidence at both widths.

**Pages updated:** wiki/testing-and-ci.md, wiki/gaps.md,
wiki/log.d/20260830T183000Z-browser-evidence-video.md

**Source:** `script/attachment_browser_evidence` and
`test/system/image_attachments_test.rb`
