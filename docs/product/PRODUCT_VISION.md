# Product Vision

*SOCLab — Building a SOC as a Product · Avi Orenstein*

## Vision

Make a complex SOC workflow **understandable, reproducible, observable, and progressively autonomous** while keeping high-impact automation controlled and evidence-based.

## Problem worth solving

The hard part is not installing Wazuh or Shuffle. It is creating a coherent operating product across deployment, detection, orchestration, integration contracts, health, recovery, evidence, and change control.

## Users

| User | Core need |
|---|---|
| **SOC Analyst** | Context and a defensible path from signal to action |
| **SOC Lead** | Confidence that changes do not silently break the operating flow |
| **Security Engineer** | Reproducible deployment, diagnosable failures, and safe recovery |

## Value proposition

SOCLab turns open security components into a **testable operating product** with explicit requirements, architecture contracts, success criteria, recovery behavior, CI safeguards, and a credible roadmap toward AI assistance.

## Product principles

1. **Outcome before tooling** — components exist to support a user outcome.
2. **Observable automation** — important behavior leaves evidence and is diagnosable.
3. **Reproducibility** — installer, tests, diagrams, decisions, and docs live in version control.
4. **Human control for high-impact decisions** — autonomy increases only after validation.
5. **Truthful communication** — Implemented, Experimental, Roadmap, and Not evidenced are distinct states.

## Current truth

The repository strongly proves the **runtime platform**: deterministic install/reset, Wazuh and Shuffle health validation, API/port/network contracts, secret-safety checks, regression tests, architecture-change governance, and recovery paths.

The repository does **not yet prove** the full security-event product journey from a committed known signal through Wazuh detection into a Shuffle workflow and final response evidence. Closing that gap is the next product milestone.

## Non-goals for the current MVP

- Production-grade enterprise SOC scale.
- Unsupervised autonomous remediation.
- Broad connector coverage without tested integrations.
- Claiming an end-to-end detection scenario before the evidence exists.
