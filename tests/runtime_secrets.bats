#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  CREDENTIALS="$REPO_ROOT/lib/credentials.sh"
  WAZUH="$REPO_ROOT/lib/wazuh.sh"
  HEALTH="$REPO_ROOT/lib/healthcheck.sh"
  SHUFFLE="$REPO_ROOT/lib/shuffle.sh"
}

@test "installer collects runtime credentials interactively" {
  run grep -F 'collect_runtime_credentials' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'read -r -s -p' "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "credential inventory is local and mode 600" {
  run grep -F 'STATE_DIR="$ROOT_DIR/state"' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'chmod 600 "$STATE_DIR/credentials.txt"' "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "compose validation does not render expanded secrets to temp files" {
  run grep -R -F 'docker compose config --quiet' "$REPO_ROOT/lib" "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -RE 'docker compose config[^#]*>[[:space:]]*/tmp/' "$REPO_ROOT/lib" "$INSTALL"
  [ "$status" -ne 0 ]
}

@test "project contains no upstream default dashboard password literal" {
  run grep -R -F 'SecretPassword' "$INSTALL" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
}

@test "healthcheck verifies stored Wazuh credentials without printing them" {
  run grep -F 'indexer-auth' "$HEALTH"
  [ "$status" -eq 0 ]
  run grep -F 'wazuh-api-auth' "$HEALTH"
  [ "$status" -eq 0 ]
}

@test "runtime password configuration is separated from source defaults" {
  run grep -F 'configure_wazuh_runtime_credentials' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_DEFAULT_PASSWORD' "$SHUFFLE"
  [ "$status" -eq 0 ]
}
