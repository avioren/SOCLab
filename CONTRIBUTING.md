# Contributing

1. Create a branch: `feat/<topic>` or `fix/<topic>`.
2. Add or update tests for behavioral changes.
3. Run `bash -n install.sh` and `bats tests` locally when available.
4. Open a GitLab Merge Request.
5. Merge only after required CI jobs pass.

Installer regressions must include a test reproducing the failure mode whenever practical.
