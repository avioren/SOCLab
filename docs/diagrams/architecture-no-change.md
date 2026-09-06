# Architecture no-change decision

This change fixes a Bash `set -u` initialization-order bug in the Shuffle worker readiness gate and suppresses expected transient curl transport noise during startup probes.

The SOCLab runtime architecture is unchanged:

- one-node Docker Swarm manager+worker
- `shuffle_shuffle` attachable core overlay
- `shuffle_swarm_executions` attachable execution overlay
- Shuffle Frontend, Backend, Orborus and OpenSearch core containers
- `shuffle-workers` execution service

No component, trust boundary, network topology, data flow, or integration contract changed. The existing Eraser runtime architecture and `shuffle-single-node-swarm.md` remain accurate.
