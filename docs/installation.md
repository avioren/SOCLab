# Installation

## Prerequisites

- Windows 11 with WSL2 Ubuntu
- Docker Desktop with WSL integration enabled
- At least 4 CPUs, 8 GiB RAM, and 50 GiB free space visible to WSL

## Clean installation

```bash
chmod +x install.sh
sudo ./install.sh install
```

The installer performs a clean lab reset, clones the `v5.0.0-beta5` Wazuh Docker repository, pulls the beta5 images, discovers the service UID/GID from those exact images, generates fresh TLS certificates, preflights all certificate mounts, starts Wazuh, verifies its endpoints, and then installs Shuffle.

## Runtime locations

- Wazuh source: `/opt/soclab/wazuh-docker`
- Shuffle source: `/opt/soclab/Shuffle`
- Credentials: `/opt/soclab/state/credentials.txt`
- Installer logs: `/tmp/soclab-full-clean-beta5-*.log`

Secrets and runtime state are not committed to Git.

## Runtime credentials

The installer does not ship or publish working passwords. Before deleting the previous lab, `sudo ./install.sh install` securely prompts for:

- Wazuh `admin` / dashboard and indexer password.
- Wazuh `kibanaserver` service password.
- Wazuh API `wazuh-wui` password.
- Shuffle administrator username/email and UI password.
- Shuffle OpenSearch administrator password.
- Shuffle API key (user-supplied or generated when Enter is pressed).
- Shuffle encryption modifier (user-supplied or generated when Enter is pressed).

Password input is not echoed. Wazuh passwords are validated against the Wazuh 5 password rules before installation proceeds.

After the clean reset, the values are recorded only on the lab host at:

```text
/opt/soclab/state/credentials.txt
```

The file is created with mode `600` and is owned by the user who invoked `sudo` when possible. It is outside this Git repository. `.gitignore` also blocks `credentials.txt`, `.env`, PEM files, and private-key files if any are accidentally copied into the project checkout.

The runtime Wazuh and Shuffle `.env`/configuration files under `/opt/soclab` are also local-only. `docker compose config --quiet` is used so interpolated secrets are not rendered into temporary Compose output files.
