# Installation

## Target platform

SOCLab is designed for one Windows 11 workstation running WSL2 Ubuntu with Docker Desktop WSL integration enabled. The Docker Desktop daemon hosts both stacks:

- Wazuh `5.0.0-beta5`: Docker Compose single-node deployment.
- Shuffle `2.2.1`: core services plus an explicit **single-node Docker Swarm** execution plane.

## Prerequisites

- Windows 11 with WSL2 Ubuntu.
- Docker Desktop running with WSL integration enabled for the Ubuntu distribution.
- Docker CLI and Docker Compose plugin reachable from WSL.
- At least 4 CPUs, 8 GiB RAM, and 50 GiB free space visible to WSL. More RAM is recommended because Wazuh and Shuffle each run OpenSearch.
- Internet access during installation to GitHub/GHCR/OpenSearch image registries.

The installer configures the required Linux kernel settings, including `vm.max_map_count=262144` and `net.ipv4.ip_forward=1`.

### Swarm assumptions

The SOCLab profile intentionally uses exactly one Swarm node. If Docker Swarm is inactive, the installer initializes it. If the Docker daemon is already part of a multi-node Swarm, the installer refuses to continue rather than modifying an unrelated cluster.

For a one-node Docker Desktop deployment no inter-host Swarm firewall opening is required. If this design is later expanded to multiple physical/VM nodes, Docker/Shuffle Swarm ports must be allowed only between those nodes (manager TCP 2377, node discovery TCP/UDP 7946, and overlay VXLAN UDP 4789).

If Docker cannot automatically choose the manager address, set:

```bash
export SOCLAB_SWARM_ADVERTISE_ADDR=<manager-address>
```

Do not set an MTU override unless the host/network actually requires one. For confirmed overlay EOF/TLS timeout problems, the installer supports:

```bash
export SHUFFLE_SWARM_MTU=<mtu>
```

## Clean installation

```bash
chmod +x install.sh
sudo ./install.sh install
```

Before destructive cleanup, the installer verifies the pinned Shuffle source tag and required container image manifests. If those release artifacts are unavailable, the existing lab is left untouched.

The clean install then performs these high-level stages:

1. Reconcile/remove SOCLab-owned Shuffle execution services and the dedicated execution overlay from any previous run.
2. Remove the previous SOCLab Compose/runtime state.
3. Apply host prerequisites and kernel settings.
4. Clone, prepare, start, and health-check Wazuh `5.0.0-beta5`.
5. Initialize/validate the one-node Docker Swarm and its ingress network.
6. Create/validate the attachable `shuffle_swarm_executions` overlay.
7. Clone pinned Shuffle `v2.2.1`, pin matching frontend/backend/Orborus/worker images, and adapt its networking for the single-node Swarm profile.
8. Start and validate Shuffle OpenSearch, Backend, Frontend, Orborus, and the Swarm worker execution plane.
9. Write the local credential inventory only after the Shuffle control, data, and execution health gates succeed.
10. Run the final combined Wazuh + Shuffle healthcheck.

## Shuffle component contract

The intended dependency chain is:

```text
Shuffle Frontend
      |
      v
Shuffle Backend <------> Shuffle OpenSearch
      |
      v
    Orborus
      |
      v
shuffle-workers (Swarm service, 1 replica)
      |
      v
temporary Shuffle app services
```

Two attachable overlay networks are used:

- `shuffle_shuffle`: core Shuffle service connectivity.
- `shuffle_swarm_executions`: Orborus/worker/app execution connectivity.

The Backend and Orborus are attached to the execution overlay. Orborus and Worker require manager-level Docker API access; app services do not receive the Docker socket.

### OpenSearch persistence and ownership

Shuffle OpenSearch remains local to this one server. Its data is bind-backed by `/opt/soclab/Shuffle/shuffle-database` through Shuffle's local volume definition. The installer does not assume a hard-coded UID/GID: it runs the pinned OpenSearch image, detects the effective `opensearch` UID/GID, changes the database directory ownership to match, and then starts the database.

The upstream OpenSearch container configuration retains its memory-lock and file-descriptor limits. Shuffle's OpenSearch host port is exposed only on loopback at `9201`; Wazuh keeps host port `9200`.

## Health gates

`sudo ./install.sh install` does not consider Shuffle healthy merely because its containers are running. The final and reusable healthchecks validate:

- Docker Swarm is active and this machine is the single active manager/worker node.
- Swarm ingress is present.
- Both Shuffle overlay networks exist, are Swarm-scoped, and are attachable.
- Shuffle frontend, backend, Orborus, and OpenSearch containers are running.
- Backend and Orborus are attached to the execution overlay.
- `/api/v1/checkusers` returns successfully, proving the Backend can use its datastore.
- Authenticated Shuffle OpenSearch cluster health is green or yellow when the local credential inventory is available.
- `shuffle-workers` exists at `1/1`, uses the pinned worker image, is attached to the execution overlay, and has Docker manager socket access.
- Recent Orborus logs do not contain missing execution-network/container-networking failures.
- Recent Backend logs do not contain the notification `updated_at` mapping failure or all-shards-failed errors that previously occurred in this lab.

Run the same checks at any time with:

```bash
./install.sh healthcheck
# or
./install.sh verify
```

## Runtime locations

- Wazuh source: `/opt/soclab/wazuh-docker`
- Shuffle source: `/opt/soclab/Shuffle`
- Shuffle database: `/opt/soclab/Shuffle/shuffle-database`
- Credentials: `/opt/soclab/state/credentials.txt`
- Installer logs: `/tmp/soclab-full-clean-beta5-*.log`

The runtime `.env`, generated credentials, certificates, and private keys are local-only and must never be committed. Compose validation uses `docker compose config --quiet` to avoid rendering interpolated secrets into temporary files.

## Reset behavior

```bash
sudo ./install.sh reset
```

Reset removes SOCLab-owned Wazuh/Shuffle runtime resources, the `shuffle-workers` service, temporary Shuffle services attached to the SOCLab execution network, and the SOCLab execution overlay. It deliberately leaves the Docker daemon in Swarm mode so it does not mutate global Docker state outside the lab's ownership boundary.
