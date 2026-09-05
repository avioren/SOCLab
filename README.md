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
install.sh credentials
```

Documentation is under `docs/` and is built by GitLab CI with MkDocs. See `docs/gitlab.md` for repository setup and authentication guidance.

## Secret handling

No passwords, tokens, private keys, generated TLS material, `.env` files, or runtime credentials belong in Git. The CI pipeline runs `scripts/check-secrets.sh` before lint/test jobs. Runtime-generated credentials are written only under `/opt/soclab` and are excluded by `.gitignore`.

## Runtime credentials

No working passwords, API keys, encryption secrets, private keys, `.env` files, or generated credential inventories belong in Git. `install.sh install` prompts for runtime secrets without echo and stores the resulting inventory only at `/opt/soclab/state/credentials.txt` with mode `600`. GitLab CI runs a blocking secret-safety scan on every pipeline.
