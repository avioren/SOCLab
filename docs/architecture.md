# Architecture

SOCLab runs on one Windows 11 workstation using WSL2 Ubuntu and Docker Desktop. Wazuh and Shuffle share the Docker daemon but keep separate OpenSearch datastores.

```text
Windows 11 / WSL2 / Docker Desktop
|
+-- Wazuh Docker Compose (single node)
|   +-- Wazuh Manager <--- agents / test telemetry
|   +-- Wazuh Indexer (OpenSearch)
|   `-- Wazuh Dashboard
|
`-- Shuffle 2.2.1
    +-- persistent/core containers
    |   +-- Frontend
    |   +-- Backend -----------+----> Shuffle OpenSearch
    |   `-- Orborus ----------|
    |
    +-- Docker Swarm: one manager+worker node
    |   +-- shuffle_shuffle (attachable core overlay)
    |   `-- shuffle_swarm_executions (attachable execution overlay)
    |       +-- Backend
    |       +-- Orborus
    |       +-- shuffle-workers (1 replica)
    |       `-- temporary app services
    |
    `-- local persistent state
        `-- /opt/soclab/Shuffle/shuffle-database
```

Runtime alert/response path:

```text
Endpoint / test telemetry
        |
        v
   Wazuh Manager
        |
        +----> Wazuh Indexer ----> Wazuh Dashboard
        |
        v
   alert / integration
        |
        v
   Shuffle Backend
        |
        v
      Orborus
        |
        v
  shuffle-workers
        |
        v
 temporary app services
        |
        v
 enrichment / response
```

## Swarm ownership boundary

SOCLab intentionally uses a one-node Swarm to make Shuffle's execution plane explicit and testable. The installer may initialize Swarm if it is inactive, but it refuses to operate on an existing multi-node Swarm. Reset removes SOCLab-owned services and its execution overlay but does not run `docker swarm leave`.

Orborus and Worker need manager-level Docker API access because they create/remove Swarm services. Shuffle app services do not receive the Docker socket.

## Data boundary

Wazuh Indexer and Shuffle OpenSearch are separate databases. Wazuh retains host port `9200`; Shuffle OpenSearch is exposed only on loopback at `9201` for diagnostics. Shuffle's database path is local to the single node and ownership is derived from the pinned OpenSearch image rather than hard-coded.

## Repository boundary

The Git repository contains installer/orchestration code, tests, documentation, architecture metadata, and future Detection-as-Code content. Wazuh and Shuffle upstream trees are cloned into `/opt/soclab` at install time and are not vendored into this repository.

Runtime credentials, `.env` files, private keys, and generated certificates remain outside Git.
