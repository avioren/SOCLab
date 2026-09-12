# SOCLab Product Requirements Document

**Version:** Portfolio MVP · evidence-aware edition

## Objective

Deliver a reproducible SOC/SOAR lab product that proves reliable deployment, runtime health, explicit integration contracts, recoverability, and — as the next milestone — one fully evidenced security-event journey from signal to response.

## Goals

- Reproducible install/reset/verify lifecycle.
- Wazuh and Shuffle component/runtime health gates.
- Explicit port/API/network/service contracts.
- CI-enforced secret safety, linting, regression tests, architecture governance, and docs validation.
- One committed end-to-end detection-to-Shuffle scenario.
- Product requirements and evidence versioned with implementation.

## Non-goals

- Production-scale enterprise SOC.
- Unsupervised autonomous remediation.
- Broad untested integration catalog.
- Claiming SOC event completion without committed proof.

## Functional requirements

| ID | Requirement | Priority | Current evidence state |
|---|---|---:|---|
| FR-01 | Trigger a deterministic security test event | P0 | **Not evidenced** |
| FR-02 | Produce the expected Wazuh detection | P0 | **Not evidenced** |
| FR-03 | Route the detection to the expected Shuffle workflow | P0 | **Not evidenced** |
| FR-04 | Complete a deterministic orchestration path | P0 | **Not evidenced for SOC scenario** |
| FR-05 | Preserve final outcome evidence | P0 | **Partial: runtime logs/health exist; SOC scenario artifact pending** |
| FR-06 | Validate component and infrastructure integration contracts | P0 | **Implemented** |
| FR-07 | Provide documented install/status/repair/reset/rebuild flows | P0 | **Implemented** |
| FR-08 | Version product/architecture evidence with implementation | P1 | **Implemented by this branch; architecture CI already enforced** |

## Non-functional requirements

| Area | Requirement | Evidence |
|---|---|---|
| Security | No working secrets/private keys/runtime credentials in Git | `scripts/check-secrets.sh`, CI `secret_scan`, `.gitignore` |
| Reproducibility | Clean install and deterministic reset paths | `install.sh`, `lib/common.sh`, installer/teardown Bats tests |
| Diagnosability | Health output must distinguish required component/contract failures | `lib/healthcheck.sh`, Wazuh API verifier, Shuffle health gates |
| Auditability | Material architecture changes require versioned architecture decision/update | `scripts/check-architecture-impact.sh`, MR CI job |
| Quality | Shell syntax, ShellCheck, Bats and MkDocs strict validation | `.gitlab-ci.yml`; latest main pipeline passed |
| Credibility | Roadmap capabilities cannot be labeled Implemented without evidence | `EVIDENCE_MATRIX.md` |

## Launch / demo criteria

### Platform demo-ready
- `./install.sh verify` succeeds locally.
- Core Wazuh and Shuffle health checks pass.
- Runtime credentials remain outside Git.
- Latest CI passes secret scan, lint, regression tests and docs validation.

### End-to-end SOC demo-ready
- FR-01 through FR-05 have committed reproducible evidence.
- One happy-path scenario can be repeated.
- At least one controlled failure can demonstrate useful diagnosis without inventing capabilities.

## Open product questions

- Which deterministic security event should become the canonical demo scenario?
- What is the smallest safe Wazuh→Shuffle integration contract to commit and test?
- Should the first response action be non-destructive enrichment/tagging to keep the demo credible and safe?
- What artifact format should store reproducible scenario evidence without exposing secrets?
