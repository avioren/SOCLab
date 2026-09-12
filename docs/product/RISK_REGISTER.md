# Risk Register

| Risk | Impact | Likelihood | Mitigation / evidence |
|---|---|---|---|
| Pre-release Wazuh instability | Demo/rebuild failure | High | Pinned version, runtime verifier, health gates, recovery docs/tests |
| Port/network/API contract drift | Flow breaks while containers appear healthy | High | Port contracts, Wazuh API verifier, Shuffle network/worker checks, regression tests |
| Secrets exposed when project becomes public | Security incident | Medium | CI secret scan, `.gitignore`, credentials outside Git, full-history review before visibility change |
| Product claims outrun implementation | Portfolio credibility damage | High | Evidence Matrix + explicit status taxonomy |
| Architecture docs become stale | Repository trust degrades | Medium | MR architecture-impact CI gate |
| Product docs become stale | Portfolio narrative diverges from code | Medium | This branch creates product system of record; CI freshness gate is V1 work |
| Live demo environment unavailable | Interview demo disrupted | Medium | Capture reproducible verify/health output and scenario evidence once implemented |
| End-to-end Wazuh→Shuffle story remains unproven | Core PM narrative weaker than runtime engineering | High | Prioritize canonical scenario before adding scope |
| AI recommendation is plausible but wrong | Unsafe future action | Future/high | Evaluation set, human approval, confidence/impact thresholds, rollback |
| Scope expands before core story is evidenced | Delayed portfolio readiness | High | Backlog prioritizes FR-01–FR-05 evidence gap |
