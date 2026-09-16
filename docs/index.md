# SOC Lab

This repository is the source of truth for a reproducible SOC/SOAR interview lab based on **Wazuh 5.0.0-beta5** and **Shuffle** on Ubuntu under WSL2 with Docker Desktop.

The supported entrypoint is `install.sh`.

```bash
sudo ./install.sh install
./install.sh healthcheck
./install.sh status
```

To reproduce the lab on another Windows 11 workstation, follow [Deploy SOCLab on Another Windows 11 Host](deploy-another-host.md). The guide covers WSL2, Docker Desktop WSL integration, Git clone/import, first installation, verification, and GitLab authentication using **your own account and credentials**.

The installer intentionally owns only `/opt/soclab`, legacy `/opt/soar-lab`, and Docker Compose projects named `single-node` and `shuffle`. It does not run global Docker prune operations.
