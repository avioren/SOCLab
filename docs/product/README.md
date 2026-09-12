# SOCLab — Product System of Record

*Technical Product Management Portfolio · Avi Orenstein*

This directory contains the product artifacts behind SOCLab. It is intentionally versioned next to implementation and tests so portfolio claims remain traceable to evidence.

> **Portfolio rule:** a capability is **Implemented** only when the repository can prove it. Otherwise it is labeled **Experimental**, **Roadmap**, or **Not evidenced**.

## Reading order

| Order | Artifact | Question answered |
|---|---|---|
| 1 | [Product Vision](PRODUCT_VISION.md) | Why does this product exist? |
| 2 | [Personas & JTBD](PERSONAS_JTBD.md) | Who are the users and what are their jobs? |
| 3 | [User Journey](USER_JOURNEY.md) | What is the signal-to-action journey? |
| 4 | [PRD](PRD.md) | What does the MVP require? |
| 5 | [Backlog](BACKLOG.md) | What work is prioritized? |
| 6 | [Roadmap](ROADMAP.md) | What comes next and why? |
| 7 | [Success Metrics](SUCCESS_METRICS.md) | How will outcomes be measured? |
| 8 | [Decision Log](DECISION_LOG.md) | Which trade-offs shaped the product? |
| 9 | [Risk Register](RISK_REGISTER.md) | What could damage reliability or credibility? |
| 10 | [AI Governance](AI_GOVERNANCE.md) | How is AI introduced safely? |
| 11 | [Demo Runbook](DEMO_RUNBOOK.md) | How should the product be demonstrated? |
| 12 | [Evidence Matrix](EVIDENCE_MATRIX.md) | Which claims are actually proven today? |
| 13 | [Architecture](../architecture.md) | What is the implemented technical architecture? |

## Capability status

| Label | Meaning |
|---|---|
| **Implemented** | Present and demonstrable from repository/runtime evidence |
| **Experimental** | Partially built or under validation; not a reliability claim |
| **Roadmap** | Intended future capability |
| **Not evidenced** | Claimed outcome does not yet have committed proof |

## Product in one paragraph

SOCLab treats a security-operations lab as a product rather than a stack of tools. The implemented platform already provides reproducible deployment, health validation, API/port/network contract checks, secret-safety CI, regression tests, recovery paths, and architecture-change governance. The next evidence gap is a committed end-to-end security scenario proving **known signal → Wazuh detection → Shuffle workflow → response/evidence**.
