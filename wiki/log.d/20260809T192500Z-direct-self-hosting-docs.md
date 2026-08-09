---
date: 2026-08-09
type: decision
pages: [self-hosting, architecture, decisions, api-cli, gaps]
---

Removed the pre-release and development-preview warnings from the README,
public self-hosting overview, and ONCE operator guide. Public onboarding now
deploys the `latest` release channel and updates it manually with
`once update HOST`; release evidence remains bound to the immutable digest
behind that channel. Successor releases must qualify a direct update and
restore from every earlier published release. The release-only
publication sentinel and its technical gates remain internal to the release
workflow.
