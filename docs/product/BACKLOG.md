# Product Backlog

| ID | Epic | User story / outcome | Priority | Status |
|---|---|---|---:|---|
| US-01 | Runtime foundation | Reproducible install/reset/verify lifecycle | P0 | **Implemented** |
| US-02 | Health | Validate Wazuh + Shuffle component/runtime contracts | P0 | **Implemented** |
| US-03 | Security | Block obvious secrets and credential-bearing files in CI | P0 | **Implemented** |
| US-04 | Architecture governance | Require architecture documentation for architecture-sensitive MR changes | P0 | **Implemented** |
| US-05 | Demo scenario | Trigger one deterministic security event | P0 | **Next** |
| US-06 | Detection | Prove the expected Wazuh alert/rule context | P0 | **Next** |
| US-07 | Orchestration | Prove Wazuh→Shuffle workflow invocation | P0 | **Next** |
| US-08 | Evidence | Preserve final workflow outcome/trace | P0 | **Next** |
| US-09 | Failure injection | Break the canonical integration and identify the failing boundary | P1 | **Experimental / planned** |
| US-10 | Product-doc freshness | Extend CI governance beyond architecture docs | P1 | **Roadmap** |
| US-11 | Dependency graph | Generate machine-readable dependency view | P1 | **Roadmap** |
| US-12 | AI assist | RAG/triage recommendations with evaluation set | P2 | **Roadmap** |
| US-13 | Governed autonomy | Policy-based low-impact actions with approval/rollback | P3 | **Roadmap** |

## Immediate product priority

Close US-05 through US-08 before adding more architecture. The runtime platform is already well engineered; the strongest portfolio improvement now is a single, evidenced user journey.
