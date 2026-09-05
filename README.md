# SOC Lab: Wazuh 5.0.0-beta5 + Shuffle

GitLab-ready automation project for a reproducible WSL2 SOC/SOAR lab.

## Quick start

```bash
chmod +x install.sh
sudo ./install.sh install
./install.sh healthcheck
```

## Commands

```text
install.sh install
install.sh healthcheck
install.sh status
install.sh logs [wazuh|shuffle|all]
install.sh reset
```

Documentation is under `docs/` and is built by GitLab CI with MkDocs. See `docs/gitlab.md` for repository setup and authentication guidance.


## Secret handling

No passwords, tokens, private keys, generated TLS material, `.env` files, or runtime credentials belong in Git. The CI pipeline runs `scripts/check-secrets.sh` before lint/test jobs. Runtime-generated credentials are written only under `/opt/soclab` and are excluded by `.gitignore`.
