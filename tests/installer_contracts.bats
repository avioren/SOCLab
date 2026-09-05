#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  WAZUH="$REPO_ROOT/lib/wazuh.sh"
  NATIVE="$REPO_ROOT/lib/wazuh_native_credentials.sh"
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

@test "installer starts stock Wazuh before native credential rotation" {
  start_line="$(grep -nF 'docker compose up -d --remove-orphans' "$INSTALL" | head -1 | cut -d: -f1)"
  rotate_line="$(grep -nF 'rotate_wazuh_runtime_credentials' "$INSTALL" | tail -1 | cut -d: -f1)"
  [ -n "$start_line" ]
  [ -n "$rotate_line" ]
  [ "$start_line" -lt "$rotate_line" ]
}

@test "native credential module uses Wazuh password tool and REST API" {
  run grep -F 'wazuh-passwords-tool.sh' "$NATIVE"
  [ "$status" -eq 0 ]
  run grep -F '/security/users/${user_id}' "$NATIVE"
  [ "$status" -eq 0 ]
}

@test "native credential path does not patch internal_users.yml" {
  run grep -R -F 'patch_internal_user_hash' "$INSTALL" "$NATIVE"
  [ "$status" -ne 0 ]
  run grep -R -F 'internal_users.yml' "$NATIVE"
  [ "$status" -ne 0 ]
}

@test "stock bootstrap credentials are discovered at runtime and not hardcoded" {
  run grep -F 'docker compose config --format json' "$NATIVE"
  [ "$status" -eq 0 ]
  run grep -F 'Stock beta5 bootstrap credentials discovered in memory' "$NATIVE"
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
