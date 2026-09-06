# SOCLab port ownership contract

SOCLab uses one explicit host-port ownership table. Container-internal ports may repeat because Docker network namespaces isolate services; host-published `(protocol, port)` tuples may not repeat.

## Application ports

| Owner | Host bind | Host port | Protocol | Container/internal port |
|---|---:|---:|---|---:|
| Wazuh syslog | `0.0.0.0` | 514 | UDP | 514 |
| Shuffle/Tenzir syslog | `0.0.0.0` | 1514 | TCP | 1514 |
| Wazuh enrollment | `0.0.0.0` | 1515 | TCP | 1515 |
| Wazuh agent events | `0.0.0.0` | 15140 | TCP | 1514 |
| Shuffle frontend HTTP | `0.0.0.0` | 3001 | TCP | 80 |
| Shuffle frontend HTTPS | `0.0.0.0` | 3443 | TCP | 443 |
| Shuffle backend API | `0.0.0.0` | 5001 | TCP | 5001 |
| Shuffle/Tenzir API | `0.0.0.0` | 5160 | TCP | 5160 |
| Wazuh dashboard | `0.0.0.0` | 8443 | TCP | 5601 |
| Wazuh indexer | `0.0.0.0` | 9200 | TCP | 9200 |
| Shuffle OpenSearch | `127.0.0.1` | 9201 | TCP | 9200 |
| Wazuh API | `127.0.0.1` | 15500 | TCP | 15500 |

Wazuh's upstream API default is TCP/55000, but the API listener port is a supported Wazuh configuration setting. SOCLab configures the manager's actual API listener to TCP/15500 in `api.yaml`, publishes host TCP/15500 to container TCP/15500, and configures `wazuh_core.hosts.default.port` in the dashboard to the same value. This is configuration-only; no Wazuh source code is changed.

The two OpenSearch services both use container TCP/9200, but they do not collide: Wazuh publishes host 9200 while Shuffle publishes host 9201, and each service runs in a separate container/network namespace.

Likewise, Wazuh manager still listens internally on TCP/1514 for agent events, while host TCP/1514 is reserved for Shuffle/Tenzir and Wazuh agent traffic is published on host TCP/15140.

## Docker Swarm ports

The single-node Shuffle execution plane additionally requires these Docker-engine ports inside the Linux host:

| Purpose | Port | Protocol |
|---|---:|---|
| Swarm manager control plane | 2377 | TCP |
| Swarm node discovery/communication | 7946 | TCP |
| Swarm node discovery/communication | 7946 | UDP |
| Swarm VXLAN overlay data plane | 4789 | UDP |

## Installer enforcement

After clean teardown and before cloning or certificate generation, the installer:

1. validates that the declared host-port contract contains no duplicate `(protocol, port)` tuples;
2. socket-binds the Swarm ports inside the Docker Linux host while Swarm is inactive;
3. publishes each application port through a short-lived Docker container using the same host bind and protocol the real service will use;
4. on failure, prints Linux listeners, Docker published ports, Windows listeners, and Windows excluded port ranges;
5. stops immediately before installing any component if a required port cannot be owned safely;
6. before first Wazuh startup, configures the manager API and dashboard API client to the declared Wazuh API port;
7. after startup, verifies the manager configuration, dashboard configuration, manager-local API reachability, and dashboard-to-manager API reachability.

This prevents late failures where Wazuh, Shuffle, OpenSearch, Tenzir, or Docker Swarm start successfully only to collide when another component tries to publish its port.
