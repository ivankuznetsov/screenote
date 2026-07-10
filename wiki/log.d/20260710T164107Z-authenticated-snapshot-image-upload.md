---
title: Authenticated snapshot image upload
type: log
date: 2026-07-10
---

# Authenticated snapshot image upload

**Action:** Added the project-scoped API v1 raw-body upload resource for prepared ScreenshotImages.

**Security:** Bodies stream through a bounded, auto-unlinked temporary file. Actual MIME is detected from bytes and must be PNG/JPEG matching both the request header and prepared type; computed SHA-256 must match the prepared identity. Error responses contain only stable codes and context, never bytes, bearer credentials, or client-local paths.

**Idempotency:** Row locking permits exactly one attachment. Identical retries return success without another blob or job; failed processing retries reuse the attachment, return to pending, and enqueue one new dimension job. Concurrent coverage proves one attachment and one initial processing job.

**Compatibility:** OAuth `mcp_write` and project API keys are supported. The existing signed-token MCP upload controller and its behavior are unchanged.

**Source:** `app/controllers/api/v1/screenshot_images_controller.rb`, `app/services/snapshots/attach_image.rb`, `app/serializers/api/v1/contract_serializer.rb`, `config/routes.rb`, and focused controller/service/integration tests.
