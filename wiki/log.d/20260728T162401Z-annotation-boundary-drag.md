---
title: Harden annotation drawing at screenshot boundaries
type: change
date: 2026-07-28
---

- Capture the active Annotorious drawing pointer so a selection can leave an image edge and resume when it returns.
- Normalize and clamp rectangle endpoints before persisting percentage geometry, including reverse drags and zero-area cleanup.
- Clean pointer listeners and capture across cancel, disconnect, image-less workspaces, and Turbo replacement.
- Add browser regression coverage for boundary, geometry, transient cleanup, and lifecycle behavior.
