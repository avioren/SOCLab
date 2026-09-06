# Architecture impact: none

This change fixes installer/runtime validation and teardown behavior only. It does not change the SOCLab runtime topology, component boundaries, network model, or single-node Docker Swarm architecture.

The cleanup sequence is now explicitly dependency-safe: quiesce Orborus, remove Shuffle execution-plane Swarm services and runtime containers attached to the SOCLab Shuffle networks, tear down the Compose project, then remove the external execution overlay. This includes stale Shuffle app/tool workloads such as `frikky/shuffle-tools`, `http_*`, `shuffle-subflow_*`, and Tenzir leftovers created by failed executions.

This is an operational lifecycle change, not an architecture change: the steady-state topology remains Wazuh plus Shuffle frontend/backend/OpenSearch/Orborus on one Swarm manager+worker node with the same execution overlay.

Editable scope for this hotfix is limited to the SOCLab installer and its supporting files. The upstream Shuffle source/runtime tree under `/opt/soclab/Shuffle` is not modified by this repository change.
