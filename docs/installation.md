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
