# SOC Lab: Wazuh 5.0.0-beta5 + Shuffle

GitLab-ready automation project for a reproducible WSL2 SOC/SOAR lab.

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

`verify` is the local full integration verification command. It runs the same end-to-end health checks as `healthcheck` against the Wazuh + Shuffle lab on your WSL machine.

Documentation is under `docs/` and is built by GitLab CI with MkDocs. See `docs/gitlab.md` for repository setup and authentication guidance.

## Product portfolio

SOCLab is also maintained as a **Technical Product Management portfolio project**. The product system of record is under [`docs/product/`](docs/product/README.md) and contains the vision, personas/JTBD, user journey, PRD, backlog, roadmap, success metrics, decisions, risks, AI governance, demo runbook, and evidence matrix.

**Portfolio rule:** no capability is labeled *Implemented* without repository/runtime evidence. The current repository strongly proves the runtime platform — reproducible install/reset, health gates, API/port/network contracts, CI safety/regression tests, architecture governance and recovery. A committed end-to-end security-event path from known signal → Wazuh detection → Shuffle workflow → final evidence is the next product milestone.

Start with: [`docs/product/EVIDENCE_MATRIX.md`](docs/product/EVIDENCE_MATRIX.md).

## CI model

Normal CI runs only on GitLab-hosted runners:

- secret safety scan
- Bash syntax and ShellCheck
- Bats unit/regression tests
- MkDocs documentation validation
- GitLab Pages build from `main`

No self-hosted GitLab Runner is required. The resource-heavy real Wazuh + Shuffle validation is intentionally run locally on the lab machine with:

```bash
./install.sh verify
```

## Secret handling

No passwords, tokens, private keys, generated TLS material, `.env` files, or runtime credentials belong in Git. The CI pipeline runs `scripts/check-secrets.sh` before lint/test jobs. Runtime-generated credentials are written only under `/opt/soclab` and are excluded by `.gitignore`.

## Runtime credentials

No working passwords, API keys, encryption secrets, private keys, `.env` files, or generated credential inventories belong in Git. `install.sh install` writes the resulting inventory only to `/opt/soclab/state/credentials.txt` with mode `600`. GitLab CI runs a blocking secret-safety scan on every pipeline.

## Installer ownership boundary

SOCLab may update `install.sh` and its supporting files under `lib/`, `tests/`, and `docs/`. The installer may generate or patch runtime configuration when provisioning the lab, but this repository does not directly maintain or modify the upstream Shuffle source tree as a codebase.
