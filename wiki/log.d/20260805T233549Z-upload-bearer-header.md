---
title: Upload credentials leave request URLs
date: 2026-08-06
tags: [security, uploads, mcp, bearer]
---

# Upload credentials leave request URLs

**Action:** Changed the legacy MCP binary-upload contract to return a credential-free endpoint plus a separate five-minute, single-use bearer and content type. The upload controller accepts the credential only through `Authorization: Bearer`, rejects query credentials, and resolves the bearer before comparing the parent screenshot ID.

**Reason:** Authentication material must not enter proxy logs, browser history, request paths, query strings, referrers, or ordinary URL telemetry. The separate header also makes invalid credentials indistinguishable across existing and missing screenshot IDs.

**Source:** `app/controllers/api/screenshot_uploads_controller.rb`, `app/tools/create_screenshot_upload_tool.rb`, `app/tools/create_multi_viewport_screenshot_tool.rb`, controller/tool/system regressions, and [[controllers/api-controllers]].
