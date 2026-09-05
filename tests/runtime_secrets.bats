#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  CREDENTIALS="$REPO_ROOT/lib/credentials.sh"
  HEALTH="$REPO_ROOT/lib/healthcheck.sh"
  VERIFIED="$REPO_ROOT/lib/verified_credentials.sh"
  STOCK="$REPO_ROOT/lib/wazuh_native_credentials.sh"
}

@test "installer performs no interactive password collection" {
  run grep -R -E 'read_password_masked|prompt_password_with_policy|Wazuh dashboard admin password|Shuffle UI admin password' "$CREDENTIALS" "$INSTALL"
  [ "$status" -ne 0 ]
  run grep -R -F '/dev/tty' "$CREDENTIALS" "$INSTALL"
  [ "$status" -ne 0 ]
  run grep -F 'No password or username prompts will be shown.' "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "browser URLs are selected automatically" {
  run grep -F 'WAZUH_DASHBOARD_BROWSER_URL="https://localhost:${WAZUH_DASHBOARD_PORT}"' "$CREDENTIALS"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_BROWSER_URL="${SHUFFLE_DETECTED_URL:-http://localhost:${SHUFFLE_FRONTEND_PORT}}"' "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "credential inventory is local and mode 600" {
  run grep -F 'STATE_DIR="$ROOT_DIR/state"' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'chmod 600 "$STATE_DIR/credentials.txt"' "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "credential inventory is written only after live verification" {
  verify_line="$(grep -nF 'verify_live_user_credentials' "$INSTALL" | tail -1 | cut -d: -f1)"
  write_line="$(grep -nF 'write_credentials_file' "$INSTALL" | tail -1 | cut -d: -f1)"
  [ -n "$verify_line" ]
  [ -n "$write_line" ]
  [ "$verify_line" -lt "$write_line" ]
}

@test "failed stored-default healthcheck removes credential inventory" {
  run grep -F 'rm -f "$STATE_DIR/credentials.txt"' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "repository does not publish a literal Wazuh default password" {
  run grep -R -F 'SecretPassword' "$INSTALL" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
}

@test "Wazuh defaults are captured and not generated" {
  run grep -F 'capture_wazuh_stock_credentials' "$STOCK"
  [ "$status" -eq 0 ]
  run grep -R -E 'generate_wazuh_password|openssl rand.*WAZUH.*PASSWORD' "$CREDENTIALS" "$STOCK" "$INSTALL"
  [ "$status" -ne 0 ]
}

@test "Wazuh verifier tests actual dashboard login endpoint" {
  run grep -F '/auth/login?dataSourceId=' "$VERIFIED"
  [ "$status" -eq 0 ]
  run grep -F 'Stock Wazuh dashboard UI login authenticated successfully' "$VERIFIED"
  [ "$status" -eq 0 ]
}

@test "Shuffle preserves upstream first-run UI behavior" {
  run grep -F 'capture_shuffle_stock_credentials' "$VERIFIED"
  [ "$status" -eq 0 ]
  run grep -F 'Shuffle upstream defines no default UI username/password' "$VERIFIED"
  [ "$status" -eq 0 ]
  run grep -R -F '/api/v1/users/register' "$VERIFIED"
  [ "$status" -ne 0 ]
  run grep -R -F 'SHUFFLE_DEFAULT_PASSWORD" ""' "$VERIFIED"
  [ "$status" -ne 0 ]
}

@test "healthcheck verifies stored Wazuh credentials without printing them" {
  run grep -F 'indexer-auth' "$HEALTH"
  [ "$status" -eq 0 ]
  run grep -F 'wazuh-api-auth' "$HEALTH"
  [ "$status" -eq 0 ]
}
