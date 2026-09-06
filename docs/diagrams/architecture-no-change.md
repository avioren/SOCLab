# Architecture impact: none

This document records implementation corrections that do not change the SOCLab component boundaries, Docker Desktop runtime model, or single-node Docker Swarm execution architecture.

## Dedicated one-node Swarm reset

For clean-install reliability, SOCLab treats the existing one-node Swarm as disposable lab state. Cleanup first verifies that the local host is an active Swarm manager and that the Swarm contains exactly one node. It then stops Shuffle Orborus, removes every Swarm service object, waits for service removal, deletes residual Swarm task containers, tears down the Wazuh/Shuffle Compose projects, and runs `docker swarm leave --force` to clear stale Raft/service/overlay state. The later Shuffle installation step initializes a fresh one-node Swarm and recreates ingress plus `shuffle_swarm_executions`.

This is necessary because deleting a Swarm task container does not delete its owning service: the Swarm manager reconciles desired state and spawns a replacement task. Removing the service object prevents dynamically created Shuffle app tasks from respawning during cleanup.

The destructive reset is refused if the existing Swarm has more than one node or the local Docker engine is not the manager. No global Docker system/image/volume prune is used.

## Wazuh API runtime state frozen after lab verification

Runtime verification in the lab proved that Wazuh 5.0.0-beta5 Dashboard actively uses the manager API entry `https://wazuh.manager` on TCP/55000. Moving the actual manager API process to TCP/15500 causes the dashboard GUI to report the API host as offline and produces authorization-token failures.

SOCLab therefore keeps the Wazuh manager API on its upstream/default internal HTTPS listener:

```text
wazuh.dashboard -> https://wazuh.manager:55000
```

The Windows/WSL host still avoids direct use of host TCP/55000 by publishing only a loopback Docker port translation:

```text
https://localhost:15500 -> wazuh.manager:55000
```

The beta5 manager API configuration file remains `/var/wazuh-manager/api/configuration/api.yaml`. SOCLab preserves the mostly-commented vendor file, removes only active top-level `host:` and `port:` keys, then appends:

```yaml
host: ["0.0.0.0", "::"]
port: 55000
```

The Wazuh dashboard plugin configuration remains HTTPS and uses the dashboard-confirmed internal endpoint:

```yaml
hosts:
  - default:
      url: https://wazuh.manager
      port: 55000
      username: wazuh-wui
      password: wazuh-wui
      run_as: true
```

`WAZUH_API_URL` remains host-only as `https://wazuh.manager`; the API port is not embedded in that environment variable.

Generated TLS certificates and private keys stay local under the runtime Wazuh tree. They are regenerated during install and are never committed to Git. The repository contains only certificate-generation logic and mount/readability checks.

Host-facing operator URLs are HTTPS by default: Wazuh Dashboard, Wazuh Indexer, Wazuh API host remap, Shuffle HTTPS frontend, and Shuffle OpenSearch. Internal Shuffle backend/worker control traffic may remain HTTP where that is the upstream application protocol.

No Wazuh or Shuffle upstream source code is modified. This correction freezes the observed beta5 runtime contract and removes the previously incorrect attempt to force the internal Wazuh API listener to TCP/15500.
