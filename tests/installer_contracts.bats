#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  WAZUH="$REPO_ROOT/lib/wazuh.sh"
  V3_CERTS="$REPO_ROOT/lib/wazuh_v3_certs.sh"
}

@test "installer is valid bash" {
  run bash -n "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "installer with no arguments shows command options instead of installing" {
  run "$INSTALL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: sudo ./install.sh <command>"* ]]
  [[ "$output" == *"Commands:"* ]]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"healthcheck"* ]]
  [[ "$output" == *"status"* ]]
  [[ "$output" == *"logs [target]"* ]]
  [[ "$output" == *"reset"* ]]
  [[ "$output" == *"credentials"* ]]
  [[ "$output" != *"SOC LAB CLEAN INSTALL"* ]]
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

@test "v3 certificate generator recreates Wazuh config certificate directories" {
  run grep -F 'rm -rf "$ca_dir" "$idx_dir" "$mgr_dir" "$dash_dir"' "$V3_CERTS"
  [ "$status" -eq 0 ]
  run grep -F 'Fresh Wazuh TLS certificates generated with image-matched ownership' "$V3_CERTS"
  [ "$status" -eq 0 ]
}

@test "installer does not discover rotate or verify Wazuh passwords" {
  run grep -R -E 'capture_wazuh_stock_credentials|rotate_wazuh_runtime_credentials|verify_runtime_credentials|verify_live_user_credentials|wazuh-passwords-tool\.sh|patch_internal_user_hash|API_PASSWORD' "$INSTALL" "$V3_CERTS" "$WAZUH"
  [ "$status" -ne 0 ]
}

@test "installer starts Wazuh using v3 health gates" {
  run grep -F 'PHASE 4/7 - START AND VERIFY WAZUH' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'WAZUH ${WAZUH_VERSION} PASSED ALL HEALTH GATES' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "dashboard HTTP liveness accepts auth responses and rejects 500" {
  source "$INSTALL"
  http_dashboard_ok 401
  http_dashboard_ok 403
  ! http_dashboard_ok 500
}

@test "indexer and API policies accept expected auth listener responses" {
  source "$INSTALL"
  http_indexer_ok 403
  http_api_ok 404
  ! http_indexer_ok 500
  ! http_api_ok 500
}
