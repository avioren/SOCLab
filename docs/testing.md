# Testing and GitLab CI

GitLab CI has four stages: `lint`, `test`, `docs`, and `integration`.

## Lint

- `bash -n install.sh`
- ShellCheck

## Unit/regression tests

Bats tests enforce the installer contracts that have already caused real failures:

- Wazuh remains pinned to `5.0.0-beta5`.
- No global Docker prune commands are introduced.
- Compose service IDs are used instead of assuming container names.
- Runtime beta5 UID/GID detection remains present.
- Certificate mount/readability preflight remains present.
- Dashboard `401` and `403` responses remain valid liveness responses.

Run locally:

```bash
bats tests
```

## Integration test

`integration_smoke` is manual and requires a dedicated GitLab Runner tagged `soclab-integration` attached to a machine where this lab is already installed. It runs the real healthcheck without making normal pipelines spend time or resources starting Wazuh and Shuffle.
