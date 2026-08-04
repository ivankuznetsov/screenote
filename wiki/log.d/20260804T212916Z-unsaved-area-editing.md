## [2026-08-04] Unsaved area editing

**Action:** Removed the duplicate custom outline from unsaved area comments, synchronized moved and resized Annotorious geometry into the pending form at pointer completion, verified edited geometry persists, and prevented small edit-handle movements from creating point comments.

**Decision:** Annotorious owns the only editable outline while an area is unsaved; Screenote's custom author marker begins after persistence. Edit gestures are classified separately from click-to-comment gestures.

**Source:** `app/javascript/controllers/annotorious_controller.js`, `test/system/annotations_test.rb`, `test/system/pages/annotations_page.rb`
