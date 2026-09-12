# Product & Architecture Decision Log

| ID | Decision | Rationale | Consequence | Status |
|---|---|---|---|---|
| D-001 | Treat SOCLab as a product, not a tool installation | Portfolio should show product ownership, not only technical setup | Requires users, requirements, metrics, roadmap and evidence | Accepted |
| D-002 | Keep Wazuh and Shuffle responsibilities explicit | Clear boundaries are easier to test and diagnose | Integration quality becomes an owned contract | Accepted |
| D-003 | Use Wazuh 5.0.0-beta5 | Learning value and current-feature exploration | Higher instability requires stronger health/recovery gates | Accepted |
| D-004 | Use one-node Shuffle Swarm execution plane | Makes Shuffle execution model explicit and testable in the lab | Requires Swarm/network/worker invariants and careful teardown | Accepted |
| D-005 | GitLab is the system of record | Tie implementation, tests, docs and decisions to change | Documentation discipline becomes part of product quality | Accepted |
| D-006 | Running container != healthy product | Real Wazuh API/configuration failure disproved process-health assumption | Listener/API/network/datastore checks became first-class requirements | Accepted |
| D-007 | Architecture-sensitive MRs must update architecture evidence | Prevent silent documentation drift | CI can block stale architecture changes | Accepted / implemented |
| D-008 | AI autonomy stays outside the MVP | Protect credibility and safety | Smaller but stronger current product claim | Accepted |
| D-009 | Close the security-event evidence gap before adding more platform scope | Runtime platform is already strong; analyst journey is not yet proven | Next priority is one canonical Wazuh→Shuffle scenario | Accepted |
