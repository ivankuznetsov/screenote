---
title: Core and SaaS capability boundary
date: 2026-08-06T00:15:00+01:00
---

- Made self-hosted project and membership policy unlimited without consulting subscription or quota rows.
- Removed subscription, checkout, portal, Stripe webhook, hosted analytics, hosted legal, upgrade, and hosted-support surfaces from self-hosted routing and rendering.
- Kept the same SaaS revision's quotas, billing, Stripe, hosted operator, landing, and legal behavior intact.
- Replaced the generic `admin?` compatibility concept with an edition-bound `saas_operator?`; self-hosted instance authority remains installation-bound and separate.
