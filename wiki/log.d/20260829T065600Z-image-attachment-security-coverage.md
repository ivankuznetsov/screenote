---
title: Image attachment security coverage ownership
date: 2026-08-29
tags: [security, coverage, attachments]
---

The release security coverage manifest now assigns every image-attachment
session/API controller and both shared authorization/streaming concerns to the
`principal` domain. This keeps controller discovery fail-closed as the feature
adds protected draft and media routes.
