# Architecture impact: none

This document records implementation corrections that do not change the SOCLab steady-state topology, component boundaries, network model, or single-node Docker Swarm architecture.

## Dedicated one-node Swarm reset

For clean-install reliability, SOCLab treats the existing one-node Swarm as disposable lab state. Cleanup first verifies that the local host is an active Swarm manager and that the Swarm contains exactly one node. It then stops Shuffle Orborus, removes every Swarm service object, waits for service removal, deletes residual Swarm task containers, tears down the Wazuh/Shuffle Compose projects, and runs `docker swarm leave --force` to clear stale Raft/service/overlay state. The later Shuffle installation step initializes a fresh one-node Swarm and recreates ingress plus `shuffle_swarm_executions`.

This is necessary because deleting a Swarm task container does not delete its owning service: the Swarm manager reconciles desired state and spawns a replacement task. Removing the service object (and, for a full clean install, resetting the dedicated one-node Swarm) prevents dynamically created Shuffle app tasks from respawning during cleanup.

The destructive reset is refused if the existing Swarm has more than one node or the local Docker engine is not the manager. No global Docker system/image/volume prune is used.

## Wazuh dashboard API configuration path correction

The Wazuh API remains configured on TCP/15500 and the SOCLab port topology is unchanged. This correction only changes how the dashboard plugin configuration for that already-decided endpoint is provisioned.

The Wazuh manager API listener remains configured in `/var/wazuh-manager/api/configuration/api.yaml`. The dashboard's Wazuh plugin manager/API endpoint belongs at `/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml`.

The pinned Wazuh 5.0.0-beta5 Docker repository does not provide `single-node/config/wazuh_dashboard/wazuh.yml`, so SOCLab now generates a minimal plugin configuration using Wazuh's supported `hosts -> default -> url/port/username/password/run_as` schema. It targets `https://wazuh.manager` on TCP/15500 with the beta5 default `wazuh-wui` credentials, applies the detected dashboard UID/GID ownership, and bind-mounts the generated file read-only into the plugin runtime path.

`opensearch_dashboards.yml` remains responsible for the dashboard/OpenSearch server configuration and is not used as the Wazuh manager API endpoint configuration.

No Wazuh or Shuffle upstream source code is modified. The components, host ports, container ports, Docker networks, and dependency graph are unchanged by this correction.
