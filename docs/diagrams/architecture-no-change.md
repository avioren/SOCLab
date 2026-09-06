# Architecture impact: none

This document records implementation corrections that do not change the SOCLab steady-state topology, component boundaries, network model, or single-node Docker Swarm architecture.

## Dedicated one-node Swarm reset

For clean-install reliability, SOCLab treats the existing one-node Swarm as disposable lab state. Cleanup first verifies that the local host is an active Swarm manager and that the Swarm contains exactly one node. It then stops Shuffle Orborus, removes every Swarm service object, waits for service removal, deletes residual Swarm task containers, tears down the Wazuh/Shuffle Compose projects, and runs `docker swarm leave --force` to clear stale Raft/service/overlay state. The later Shuffle installation step initializes a fresh one-node Swarm and recreates ingress plus `shuffle_swarm_executions`.

This is necessary because deleting a Swarm task container does not delete its owning service: the Swarm manager reconciles desired state and spawns a replacement task. Removing the service object (and, for a full clean install, resetting the dedicated one-node Swarm) prevents dynamically created Shuffle app tasks from respawning during cleanup.

The destructive reset is refused if the existing Swarm has more than one node or the local Docker engine is not the manager. No global Docker system/image/volume prune is used.

## Wazuh 5.0.0-beta5 API configuration path correction

The Wazuh API remains configured on TCP/15500 and the SOCLab port topology is unchanged.

For the pinned `wazuh/wazuh-manager:5.0.0-beta5` image, the actual API configuration file is:

`/var/wazuh-manager/api/configuration/api.yaml`

This was verified directly against the beta5 image and then validated at runtime: after adding active API host/port settings, the manager served the API on TCP/15500 and no longer served it on TCP/55000. The `/var/ossec/api/configuration/api.yaml` path belongs to older/current Wazuh layouts and is not valid for this beta5 image.

SOCLab explicitly configures:

```yaml
host: ['0.0.0.0', '::']
port: 15500
```

The beta5 `api.yaml` is mostly commented by default. The installer therefore replaces a matching active or commented `host`/`port` setting when one exists, and otherwise appends an active setting. It then verifies both values before continuing.

The Docker Compose publication is host TCP/15500 to container TCP/15500. It is not a host-port translation to the upstream default TCP/55000.

The dashboard's Wazuh plugin manager/API endpoint belongs at `/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml`.

The pinned Wazuh 5.0.0-beta5 Docker repository does not provide `single-node/config/wazuh_dashboard/wazuh.yml`, so SOCLab generates a minimal plugin configuration using Wazuh's supported `hosts -> default -> url/port/username/password/run_as` schema. It targets `https://wazuh.manager` on TCP/15500 with the beta5 default `wazuh-wui` credentials, applies the detected dashboard UID/GID ownership, and bind-mounts the generated file read-only into the plugin runtime path.

Wazuh Docker also initializes the dashboard API host from the `WAZUH_API_URL` environment variable. That variable is a host/base URL, not a host-plus-port field. SOCLab therefore keeps it at `WAZUH_API_URL=https://wazuh.manager` and stores the non-default API port only in `wazuh.yml`. Supplying `https://wazuh.manager:15500` in the environment can cause the image initializer to append its own default port and produce a malformed endpoint such as `https://wazuh.manager:15500:55000`.

Runtime verification checks `/var/wazuh-manager/api/configuration/api.yaml` for the expected host and TCP/15500 listener configuration, the host-only dashboard environment value, the read-only `wazuh.yml` mount, `port: 15500` in the live plugin configuration, dashboard-to-manager connectivity on TCP/15500, and absence of fallback/malformed TCP/55000 manager URLs in recent dashboard logs.

`opensearch_dashboards.yml` remains responsible for the dashboard/OpenSearch server configuration and is not used as the Wazuh manager API endpoint configuration.

No Wazuh or Shuffle upstream source code is modified. The components, host ports, container ports, Docker networks, and dependency graph are unchanged by this correction.
