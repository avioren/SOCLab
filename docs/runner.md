# Local Integration Verification

No self-hosted GitLab Runner is required for this project.

GitLab-hosted runners handle the lightweight CI jobs: secret scanning, shell linting, Bats unit/regression tests, and documentation builds.

The resource-heavy real deployment check is run directly on the WSL lab machine:

```bash
./install.sh verify
```

For a from-scratch reproducibility test:

```bash
sudo ./install.sh install
./install.sh verify
```

This design keeps the interview lab under explicit local control and avoids maintaining a dedicated runner.
