# Shuffle single-node Swarm architecture decision

Status: **adopted for SOCLab**

## Decision

SOCLab runs Shuffle `2.2.1` with an explicit one-node Docker Swarm execution plane on the same Docker Desktop daemon used by WSL2. Wazuh remains Docker Compose based.

## Required topology

```text
Frontend -> Backend <-> OpenSearch
              |
              +--------------------+
                                   |
Backend + Orborus --- shuffle_swarm_executions (attachable overlay)
          |
          v
   shuffle-workers (1/1)
          |
          v
 temporary app services
```

The core `shuffle` network is also converted to an attachable Swarm overlay. The execution network is named `shuffle_swarm_executions` by default.

## Installation invariants

The installer must fail unless all of these are true:

1. Docker daemon is reachable and Compose is available.
2. Swarm is active with this server as an active manager and the Swarm has exactly one node.
3. Swarm ingress exists.
4. The dedicated execution overlay exists, is Swarm-scoped, and is attachable.
5. Shuffle release/source and frontend/backend/Orborus/worker image versions are pinned coherently.
6. Shuffle OpenSearch data ownership matches the UID/GID detected from the pinned OpenSearch image.
7. Backend can use OpenSearch (`/api/v1/checkusers`).
8. Orborus is attached to the execution overlay and can access the Docker manager API.
9. `shuffle-workers` reaches `1/1`, uses the pinned image, shares the execution overlay, and has Docker manager socket access.
10. Recent Orborus/Backend logs do not contain known execution-network or OpenSearch mapping/shard failures.

## Cleanup invariant

SOCLab may remove only its own Swarm worker/app services and dedicated execution overlay. It must not run global Docker prune commands or force the daemon to leave Swarm mode.

## Data invariant

Shuffle OpenSearch is single-node/local for this lab. Its data path must not float across Swarm nodes. Wazuh and Shuffle OpenSearch remain separate datastores.

## Architecture documentation

GitLab is the authoritative source for this architecture decision. Any topology or installation-flow change is documented and reviewed directly in this repository under `docs/diagrams/`; no external diagram service is required.
