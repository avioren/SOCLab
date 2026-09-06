# Architecture impact: none

This document records implementation corrections that do not change the SOCLab steady-state topology, component boundaries, network model, or single-node Docker Swarm architecture.

## Dedicated one-node Swarm reset

For clean-install reliability, SOCLab treats the existing one-node Swarm as disposable lab state. Cleanup first verifies that the local host is an active Swarm manager and that the Swarm contains exactly one node. It then stops Shuffle Orborus, removes every Swarm service object, waits for service removal, deletes residual Swarm task containers, tears down the Wazuh/Shuffle Compose projects, and runs `docker swarm leave --force` to clear stale Raft/service/overlay state. The later Shuffle installation step initializes a fresh one-node Swarm and recreates ingress plus `shuffle_swarm_executions`.

This is necessary because deleting a Swarm task container does not delete its owning service: the Swarm manager reconciles desired state and spawns a replacement task. Removing the service object (and, for a full clean install, resetting the dedicated one-node Swarm) prevents dynamically created Shuffle app tasks from respawning during cleanup.

The destructive reset is refused if the existing Swarm has more than one node or the local Docker engine is not the manager. No global Docker system/image/volume prune is used.

## Wazuh dashboard API configuration path correction

The Wazuh API remains configured on TCP/15500 and the SOCLab port topology is unchanged. This correction only changes which Wazuh dashboard configuration file is used to express that already-decided endpoint.

The Wazuh manager API listener remains configured in `/var/wazuh-manager/api/configuration/api.yaml`. The dashboard's Wazuh plugin manager/API endpoint is configured in `/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml`, which is the plugin-specific configuration file. SOCLab patches the pinned `single-node/config/wazuh_dashboard/wazuh.yml` and bind-mounts it read-only into that runtime path so the beta5 image cannot regenerate the upstream default TCP/55000 endpoint.

`opensearch_dashboards.yml` remains responsible for the dashboard/OpenSearch server configuration and is no longer used as the Wazuh manager API port assertion.

No Wazuh or Shuffle upstream source code is modified. The components, host ports, container ports, Docker networks, and dependency graph are unchanged by this correction.
