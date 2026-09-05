# SOC Lab

This repository is the source of truth for a reproducible SOC/SOAR interview lab based on **Wazuh 5.0.0-beta5** and **Shuffle** on Ubuntu under WSL2 with Docker Desktop.

The supported entrypoint is `install.sh`.

```bash
sudo ./install.sh install
./install.sh healthcheck
./install.sh status
```

The installer intentionally owns only `/opt/soclab`, legacy `/opt/soar-lab`, and Docker Compose projects named `single-node` and `shuffle`. It does not run global Docker prune operations.
