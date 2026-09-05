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

The installer performs a clean lab reset, clones the `v5.0.0-beta5` Wazuh Docker repository, pulls the beta5 images, discovers the service UID/GID from those exact images, generates fresh TLS certificates, preflights all certificate mounts, starts Wazuh, verifies its endpoints and real UI login, installs Shuffle, creates the first Shuffle admin through Shuffle's API, verifies that login, and only then writes the local credential inventory.

## What the installer asks you for

At the start of installation it asks for the user-facing accounts you will really use:

- Wazuh dashboard `admin` password.
- Shuffle administrator username/email.
- Shuffle administrator UI password.

Password input is not echoed. Internal service credentials (`kibanaserver`, `wazuh-wui`, Shuffle OpenSearch, and encryption material) are generated locally and are never published to Git.

After Wazuh and Shuffle are running, the installer shows the detected browser endpoints and asks you to confirm or override:

- Wazuh dashboard URL.
- Shuffle URL.

Use the localhost defaults when you browse from the same Windows/WSL workstation. If you normally browse through another hostname or IP, enter that value instead. The exact confirmed values are what get written to `credentials.txt`.

## Credential verification contract

The credential inventory is an output of a successful installation, not a source of guessed defaults.

Before `credentials.txt` is created, the installer verifies:

1. Wazuh `admin` authenticates directly to the indexer.
2. Wazuh `wazuh-wui` authenticates to the server API.
3. The same Wazuh `admin` credential succeeds through the actual dashboard `/auth/login` endpoint.
4. Shuffle's first admin is registered using the username/password you supplied.
5. The Shuffle username/password then succeeds against Shuffle's login API.
6. Both stacks pass the final service healthcheck.

If the final stored-credential healthcheck fails, the installer deletes `credentials.txt` rather than leaving a file containing values that were not verified.

## Runtime locations

- Wazuh source: `/opt/soclab/wazuh-docker`
- Shuffle source: `/opt/soclab/Shuffle`
- Credentials: `/opt/soclab/state/credentials.txt`
- Installer logs: `/tmp/soclab-full-clean-beta5-*.log`

The credential file is created with mode `600` and is owned by the user who invoked `sudo` when possible. It is outside this Git repository. `.gitignore` also blocks `credentials.txt`, `.env`, PEM files, and private-key files if any are accidentally copied into the project checkout.

The runtime Wazuh and Shuffle `.env`/configuration files under `/opt/soclab` are local-only. `docker compose config --quiet` is used so interpolated secrets are not rendered into temporary Compose output files.
