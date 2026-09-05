#!/usr/bin/env bash
set -euo pipefail
# Minimal fake Docker command for future unit tests. Extend per test case.
printf 'fake-docker: %s\n' "$*" >&2
exit "${FAKE_DOCKER_EXIT:-0}"
