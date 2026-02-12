---
status: pending
priority: p1
issue_id: "001"
tags: [code-review, security]
dependencies: []
---

# No File Upload Validation on Screenshot Model and MCP Tool

## Problem Statement
The Screenshot model has no content type or file size validation on Active Storage attachments. The CreateScreenshotTool accepts arbitrary base64 data with an attacker-controlled mime_type parameter. This allows uploading arbitrary file types (SVG with JS, HTML, executables) and unlimited file sizes, risking storage exhaustion and potential XSS.

## Findings
- `app/models/screenshot.rb`: `has_one_attached :image` with no content_type or size validation
- `app/tools/create_screenshot_tool.rb`: `Base64.decode64(image_base64)` with no size limit; `mime_type` parameter passed directly as `content_type` with no allowlist
- Agents: security-sentinel (C1, C2), architecture-strategist, dhh-rails-reviewer

## Proposed Solutions

### Option A: Rails Active Storage Validations (Recommended)
Add native Rails validations to Screenshot model:
```ruby
validates :image, content_type: ['image/png', 'image/jpeg'], size: { less_than: 20.megabytes }
```
And validate base64 length and mime_type allowlist in CreateScreenshotTool before decoding.
- Pros: Simple, uses Rails built-ins, catches both web and MCP uploads
- Cons: None significant
- Effort: Small
- Risk: Low

### Option B: Custom validation + magic bytes check
Validate mime_type allowlist, base64 length before decode, and verify magic bytes match claimed type.
- Pros: Most thorough
- Cons: More code
- Effort: Medium
- Risk: Low

## Technical Details
- Files: `app/models/screenshot.rb`, `app/tools/create_screenshot_tool.rb`

## Acceptance Criteria
- [ ] Screenshot model validates content_type (png/jpeg only)
- [ ] Screenshot model validates file size (max 20MB)
- [ ] CreateScreenshotTool validates mime_type against allowlist
- [ ] CreateScreenshotTool validates base64 length before decoding
- [ ] Tests cover invalid file type and oversized file rejection

## Work Log
- 2026-02-12: Created from code review findings (security-sentinel, architecture-strategist)
