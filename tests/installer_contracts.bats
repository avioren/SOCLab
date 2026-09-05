#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  WAZUH="$REPO_ROOT/lib/wazuh.sh"
  STOCK="$REPO_ROOT/lib/wazuh_native_credentials.sh"
}

@test "installer is valid bash" {
  run bash -n "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "installer pins Wazuh beta5" {
  run grep -F 'WAZUH_VERSION="5.0.0-beta5"' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "installer does not contain executable global Docker prune commands" {
  run grep -RE '^[[:space:]]*docker[[:space:]]+(system|volume|image)[[:space:]]+prune' "$INSTALL" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
}

@test "Wazuh service discovery uses Compose service IDs" {
  run grep -F 'docker compose ps -q --all "$service"' "$WAZUH"
  [ "$status" -eq 0 ]
}

@test "Wazuh image account detection is dynamic" {
  run grep -F 'detect_wazuh_image_accounts' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'id -u' "$WAZUH"
  [ "$status" -eq 0 ]
}

@test "certificate mount preflight exists" {
  run grep -F 'verify_wazuh_cert_mounts' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'test -r' "$WAZUH"
  [ "$status" -eq 0 ]
}

@test "stock Wazuh credentials are discovered from rendered Compose" {
  run grep -F 'capture_wazuh_stock_credentials' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'docker compose config --format json' "$STOCK"
  [ "$status" -eq 0 ]
  run grep -F 'Stock Wazuh credentials captured in memory without modification' "$STOCK"
  [ "$status" -eq 0 ]
}

@test "installer does not rotate or rewrite Wazuh passwords" {
  run grep -R -F 'rotate_wazuh_runtime_credentials' "$INSTALL" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
  run grep -R -F 'wazuh-passwords-tool.sh' "$INSTALL" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
  run grep -R -F 'patch_internal_user_hash' "$INSTALL" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
}

@test "installer starts Wazuh with upstream defaults unchanged" {
  run grep -F 'Starting Wazuh with the upstream default credentials unchanged' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "dashboard HTTP liveness accepts auth responses and rejects 500" {
  source "$INSTALL"
  http_dashboard_ok 401
  http_dashboard_ok 403
  ! http_dashboard_ok 500
}

@test "indexer and API policies accept expected auth/listener responses" {
  source "$INSTALL"
  http_indexer_ok 403
  http_api_ok 404
  ! http_indexer_ok 500
  ! http_api_ok 500
}
