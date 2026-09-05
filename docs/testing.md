# Testing and GitLab CI

GitLab CI has four stages: `security`, `lint`, `test`, and `docs`. They run on GitLab-hosted runners; no self-hosted runner is required.

## Lint

- `bash -n install.sh` and every `lib/*.sh` module
- ShellCheck across the installer, libraries, and security scripts

## Unit/regression tests

Bats tests enforce the installer contracts that have already caused real failures:

- Wazuh remains pinned to `5.0.0-beta5`.
- No global Docker prune commands are introduced.
- Compose service IDs are used instead of assuming container names.
- Runtime beta5 UID/GID detection remains present.
- Certificate mount/readability preflight remains present.
- Dashboard `401` and `403` responses remain valid liveness responses.
- Runtime credentials are prompted rather than committed.
- The local credential inventory remains mode `600`.
- Compose validation does not render interpolated secrets into temporary files.
- GitLab CI does not depend on a self-hosted `soclab-integration` runner.
- The local `verify` command remains available for end-to-end lab checks.

Run locally:

```bash
bats tests
```

## Local integration verification

The real Wazuh + Shuffle integration test runs on the WSL lab itself instead of in GitLab CI:

```bash
./install.sh verify
```

This checks the installed Wazuh indexer, manager, dashboard, indexer Security endpoint, Wazuh HTTPS/API reachability, stored runtime credentials where available, Shuffle frontend, and Shuffle OpenSearch authentication where directly exposed.

Use a full clean deployment when you want to prove reproducibility from scratch:

```bash
sudo ./install.sh install
./install.sh verify
```

Keeping this local avoids operating a GitLab Runner and prevents routine commits from rebuilding or wiping the interview lab.

## Secret-safety gate

The first GitLab CI stage runs `scripts/check-secrets.sh`. It rejects common private-key/token formats, secret-bearing file types, and literal credential assignments. `tests/runtime_secrets.bats` also protects the runtime-only credential design and verifies that Compose validation does not emit interpolated secrets into `/tmp` files.
