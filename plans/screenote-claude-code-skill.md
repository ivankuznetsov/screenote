# feat: Create `/screenote` Claude Code Skill for Visual Feedback Loop

## Overview

A Claude Code skill at `.claude/skills/screenote/SKILL.md` with two modes:

- **Capture** (`/screenote [url-or-description]`): Screenshot via Playwright MCP, upload to Screenote MCP, return annotation URL
- **Feedback** (`/screenote feedback [screenshot-id]`): Retrieve annotations with cropped images, formatted for Claude to act on

## Implementation

### Step 1: Add `image_path` parameter to `CreateScreenshotTool`

The current `create_screenshot` MCP tool only accepts `image_base64`. Playwright MCP saves screenshots as files. Piping megabytes of base64 through Claude's context window will silently truncate (Bash output caps at 30K chars).

Add an `image_path` parameter to `CreateScreenshotTool` so it can read the file directly from disk. This avoids base64 encoding entirely.

**File:** `app/tools/create_screenshot_tool.rb`
- Add `image_path` string argument (alternative to `image_base64`)
- If `image_path` is provided, read the file, detect MIME type, attach directly
- Keep `image_base64` for backward compatibility (remote MCP clients can't share filesystem)
- Validate: exactly one of `image_path` or `image_base64` must be provided

### Step 2: Write the SKILL.md

**File:** `.claude/skills/screenote/SKILL.md`

~50-80 lines total:
- YAML frontmatter: name, description, allowed-tools (Playwright MCP + Screenote MCP + Bash + Read), argument-hint
- Capture mode: navigate, screenshot to known absolute path, call `create_screenshot` with `image_path`, return URL
- Feedback mode: `list_annotations` (open only), `get_annotation` for each (with cropped image), present structured feedback
- Resolve is opt-in: "Ask the user before resolving annotations"
- URL resolution: one sentence -- "Resolve input to a URL; for relative paths, prepend the dev server URL from CLAUDE.md"
- No reference files. No subdirectories. One file.

### Step 3: Test end-to-end

- Verify `/screenote http://localhost:3005` captures and uploads
- Verify `/screenote feedback` retrieves annotations with images

## Key Decisions (from review)

- **No base64 through context** -- `image_path` parameter reads from disk
- **No reference docs** -- MCP tools are self-documenting
- **No region-to-words mapping** -- Claude sees the cropped image
- **Viewport-only default** (not fullPage) -- avoids oversized screenshots
- **Resolve is opt-in** -- Claude asks before marking annotations resolved
- **Single skill, two modes** -- `/screenote` for capture, `/screenote feedback` for retrieval
