# Evidence Matrix

*SOCLab — Building a SOC as a Product · Technical Product Management Portfolio · Avi Orenstein*

This matrix is the credibility layer for the public portfolio. A capability is marked **Implemented** only when the repository contains concrete evidence for it. Runtime-only claims are explicitly separated from repository/CI evidence.

> Reviewed against `main` at commit `ca6219a329ba33808458dff7dbd45b447bfd79c8` and successful pipeline `#2824467601`.

| Capability / claim | Status | Repository evidence | What is still needed |
|---|---|---|---|
| Reproducible installer / operator entrypoint | **Implemented** | `install.sh`; documented `install`, `verify`, `healthcheck`, `status`, `logs`, `reset`, `credentials` commands in `README.md` | Keep clean-run evidence for interview fallback |
| Wazuh + Shuffle component health validation | **Implemented** | `lib/healthcheck.sh` validates Wazuh services, Wazuh API config, Shuffle frontend/backend/OpenSearch/Orborus/workers, networks and datastore reachability | Capture a successful local `./install.sh verify` output as demo evidence |
| Runtime integration-contract validation | **Implemented — infrastructure scope** | Wazuh API listener/dashboard contract, port contracts, network attachment, worker image/replica/socket checks; `tests/port_contracts.bats`, `tests/installer_contracts.bats` | This does **not** yet prove alert-to-SOAR routing |
| Wazuh API 15500 host remap / 55000 internal contract | **Implemented + tested** | `lib/wazuh_dashboard_api_override.sh`, `lib/wazuh.sh`, `tests/port_contracts.bats`, reusable health verifier | Runtime screenshot/output optional for portfolio |
| Shuffle single-node Swarm execution plane | **Implemented + tested** | `lib/shuffle.sh`, `lib/healthcheck.sh`, `tests/installer_contracts.bats`, `docs/diagrams/shuffle-single-node-swarm.md` | Capture one healthy runtime output for demo evidence |
| Deterministic teardown / repair / rebuild behavior | **Implemented in code + regression tests** | installer/reset cleanup paths, `scripts/repair-shuffle-workflows.sh`, installer/teardown Bats tests, architecture decision notes | Keep one clean rebuild transcript for interview evidence |
| Secret-safety enforcement | **Implemented + CI enforced** | `scripts/check-secrets.sh`; `secret_scan` stage in `.gitlab-ci.yml`; `.gitignore`; runtime credentials kept outside Git | Before public visibility, also review full Git history manually/with secret tooling |
| CI lint + regression tests + docs validation | **Implemented + passing** | `.gitlab-ci.yml`; latest `main` pipeline `2824467601` status `success`; Bats test suite; ShellCheck; MkDocs strict build | None for repository claim |
| Architecture-document freshness gate | **Implemented for merge requests** | `scripts/check-architecture-impact.sh`; `architecture_impact` MR job; versioned `docs/diagrams/` decisions | Product-doc freshness gate is not yet automated |
| Known security test signal is reproducible | **Not evidenced in repository** | No dedicated detection fixture/scenario found in current repo | Add a deterministic test event + run instructions + captured evidence |
| Wazuh detects the expected security event | **Not evidenced in repository** | Installer validates Wazuh runtime, but no detection scenario/alert fixture proves FR-02 | Add detection rule/scenario and expected alert evidence |
| Wazuh detection routes to a Shuffle workflow | **Not evidenced in repository** | No committed webhook/integration contract or invocation test found | Add Wazuh→Shuffle integration config/test and workflow invocation trace |
| Deterministic SOC workflow reaches response/evidence | **Not evidenced in repository** | Shuffle runtime health is proven; SOC workflow outcome is not | Add one end-to-end scenario with outcome/evidence artifact |
| Failure injection identifies alert-routing boundary | **Experimental / demo target** | Infrastructure contract checks can identify runtime/config boundaries | Add explicit failure-injection test for the Wazuh→Shuffle scenario |
| Product artifacts version with implementation | **Implemented by this branch; partial automation** | `docs/product/` plus existing architecture-impact CI | Optionally extend CI to require product-doc updates for product-sensitive changes |
| Dependency graph / configuration drift | **Roadmap** | Architecture metadata exists but no generated dependency/drift engine | V1 implementation + CI evidence |
| AI triage / RAG | **Roadmap** | Governance and evaluation requirements documented only | Evaluation set, implementation, measured quality |
| Governed autonomy | **Roadmap** | Policy model documented only | Policy enforcement, approvals, rollback and safety metrics |
| Public repository | **Not yet public** | Project visibility is currently private | Complete security/history review, then change visibility deliberately |

## Current interview-safe claim

SOCLab currently proves a **reproducible and heavily validated SOC/SOAR runtime platform**: deterministic install/reset, component health, network/port/API contracts, secret safety, CI regression tests, architecture-change governance, and documented recovery paths.

The repository does **not yet prove** the portfolio's full security-event journey — **known signal → Wazuh alert → Shuffle workflow → decision/response → evidence**. That is the next evidence gap to close before presenting the end-to-end workflow as Implemented.

## Rule

**No evidence → no Implemented label.**

Historical incidents can be used as product-learning evidence even when the resulting future automation remains Experimental or Roadmap.
