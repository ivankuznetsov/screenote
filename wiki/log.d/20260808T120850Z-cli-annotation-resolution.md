---
date: 2026-08-08
type: correction
pages: [api-cli, commands, gaps, roadmap]
---

Corrected the documented agent feedback boundary after verifying that the
public Screenote CLI `main` branch implements `screenote annotation resolve`
with an optional resolution comment. Agents can read, reply to, and resolve
annotation threads through the CLI; reopening remains web-only.

The command is not described as a supported immutable artifact yet. The first
supported Screenote release must pin an exact public CLI tag that contains it.

Source: public CLI commit `c28ac8b3b1b720ef60275e5f59db3a96f8cfa98b`
(`internal/cli/annotation.go`),
`app/controllers/api/v1/annotation_resolutions_controller.rb`, and
`config/routes.rb`.
