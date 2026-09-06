# SOC Lab: Wazuh 5.0.0-beta5 + Shuffle 2.2.1 Swarm

GitLab-ready automation for a reproducible WSL2 SOC/SOAR lab on Docker Desktop.

Shuffle uses an explicit **single-node Docker Swarm** execution plane. Wazuh remains a Docker Compose single-node deployment on the same Docker daemon.

## Quick start

```bash
chmod +x install.sh
sudo ./install.sh install
./install.sh verify
```

## Commands

```text
install.sh install
install.sh verify
install.sh healthcheck
install.sh status
install.sh logs [wazuh|shuffle|all]
install.sh reset
install.sh credentials
```

`install` is destructive only to SOCLab-owned runtime state under `/opt/soclab`, the legacy `/opt/soar-lab` path, SOCLab Compose resources, the `shuffle-workers` service, temporary Shuffle execution services attached to the dedicated execution overlay, and that overlay itself. It does not run global Docker prune commands and does not force the Docker daemon to leave Swarm mode.

`verify` runs the same end-to-end health gates as `healthcheck`, including Wazuh services plus Shuffle Swarm state, overlay networks, Backend/OpenSearch connectivity, Orborus, and the `shuffle-workers` execution service.

Documentation is under `docs/` and is validated with MkDocs in GitLab CI.

## Shuffle runtime model

The installer pins Shuffle `2.2.1` and its frontend, backend, Orborus, and worker images as one release set. Before deleting the current lab it verifies that the source tag and required image manifests exist.

For Shuffle it then:

1. Initializes Docker Swarm when needed and requires this machine to be the only active manager/worker node.
2. Enables IPv4 forwarding and validates the Swarm ingress overlay.
3. Creates the attachable `shuffle_swarm_executions` overlay.
4. Converts Shuffle's core `shuffle` network to an attachable Swarm overlay.
5. Starts the pinned Shuffle control/data components.
6. Detects the OpenSearch container UID/GID and applies matching ownership to the local bind-mounted database path.
7. Requires Backend-to-OpenSearch health before continuing.
8. Requires Orborus to establish a healthy `shuffle-workers` Swarm service on the execution overlay with manager Docker API access.
9. Rejects recent execution-network and OpenSearch mapping/shard errors.

## CI model

GitLab-hosted CI runs:

- secret safety scan
- Bash syntax and ShellCheck
- Bats unit/regression contracts
- architecture-impact enforcement
- MkDocs validation and Pages build

The resource-heavy real Wazuh + Shuffle validation remains local to the lab machine:

```bash
./install.sh verify
```

## Secret handling

No passwords, tokens, private keys, generated TLS material, `.env` files, or runtime credentials belong in Git. Runtime-generated Shuffle credentials are stored only at `/opt/soclab/state/credentials.txt` with mode `600`; Compose configuration is validated with `docker compose config --quiet` so interpolated secrets are not written to temporary rendered Compose files.
