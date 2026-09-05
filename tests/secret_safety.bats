#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "repository secret safety scan passes" {
  run "$REPO_ROOT/scripts/check-secrets.sh" "$REPO_ROOT"
  [ "$status" -eq 0 ]
}

@test "installer does not publish a literal Wazuh dashboard password" {
  run grep -E 'WAZUH_DASHBOARD_PASSWORD[^=]*=[A-Za-z0-9]' "$REPO_ROOT/install.sh"
  [ "$status" -ne 0 ]
}
