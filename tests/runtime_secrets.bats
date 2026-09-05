#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  CREDENTIALS="$REPO_ROOT/lib/credentials.sh"
  HEALTH="$REPO_ROOT/lib/healthcheck.sh"
  VERIFIED="$REPO_ROOT/lib/verified_credentials.sh"
  NATIVE="$REPO_ROOT/lib/wazuh_native_credentials.sh"
}

@test "installer collects user-facing runtime credentials interactively" {
  run grep -F 'collect_runtime_credentials' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'Wazuh dashboard admin password' "$CREDENTIALS"
  [ "$status" -eq 0 ]
  run grep -F 'Shuffle UI admin password' "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "password fields show mask characters while usernames remain visible" {
  run grep -F 'read_password_masked' "$CREDENTIALS"
  [ "$status" -eq 0 ]
  run grep -F "printf '*' >/dev/tty" "$CREDENTIALS"
  [ "$status" -eq 0 ]
  run grep -F 'IFS= read -r -p "Shuffle admin username/email' "$CREDENTIALS"
  [ "$status" -eq 0 ]
  run grep -F 'IFS= read -r -s -p "Shuffle admin username/email' "$CREDENTIALS"
  [ "$status" -ne 0 ]
}

@test "Wazuh policy follows native indexer tool special-character contract" {
  run bash -c 'source "$1"; wazuh_password_policy_ok "Valid1.x"' _ "$CREDENTIALS"
  [ "$status" -eq 0 ]
  run bash -c 'source "$1"; wazuh_password_policy_ok "Valid1!x"' _ "$CREDENTIALS"
  [ "$status" -ne 0 ]
  run grep -F 'one of . * + ? - (Wazuh native tool policy)' "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "Shuffle password policy still accepts exclamation mark" {
  run bash -c 'source "$1"; shuffle_password_policy_ok "Valid1!x"' _ "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "browser URLs are confirmed interactively and remain visible" {
  run grep -F 'collect_browser_urls' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'prompt_browser_url "Wazuh dashboard URL"' "$CREDENTIALS"
  [ "$status" -eq 0 ]
  run grep -F 'prompt_browser_url "Shuffle URL"' "$CREDENTIALS"
  [ "$status" -eq 0 ]
  run grep -F 'IFS= read -r -p "$label [$default]: " value' "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "credential inventory is local and mode 600" {
  run grep -F 'STATE_DIR="$ROOT_DIR/state"' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'chmod 600 "$STATE_DIR/credentials.txt"' "$CREDENTIALS"
  [ "$status" -eq 0 ]
}

@test "credential inventory is written only after live credential verification" {
  verify_line="$(grep -nF 'verify_live_user_credentials' "$INSTALL" | tail -1 | cut -d: -f1)"
  write_line="$(grep -nF 'write_credentials_file' "$INSTALL" | tail -1 | cut -d: -f1)"
  [ -n "$verify_line" ]
  [ -n "$write_line" ]
  [ "$verify_line" -lt "$write_line" ]
}

@test "failed stored-credential healthcheck removes the inventory" {
  run grep -F 'rm -f "$STATE_DIR/credentials.txt"' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "project contains no upstream default dashboard password literal" {
  run grep -R -F 'SecretPassword' "$INSTALL" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
}

@test "bootstrap credentials are held in memory and cleared after rotation" {
  run grep -F 'WAZUH_BOOTSTRAP_ADMIN_PASSWORD' "$NATIVE"
  [ "$status" -eq 0 ]
  run grep -F 'unset WAZUH_BOOTSTRAP_ADMIN_PASSWORD' "$NATIVE"
  [ "$status" -eq 0 ]
}

@test "Wazuh credential verifier tests the actual dashboard login endpoint" {
  run grep -F '/auth/login?dataSourceId=' "$VERIFIED"
  [ "$status" -eq 0 ]
  run grep -F 'Wazuh dashboard UI login authenticated successfully' "$VERIFIED"
  [ "$status" -eq 0 ]
}

@test "Shuffle does not trust default UI bootstrap credentials" {
  run grep -F 'SHUFFLE_DEFAULT_USERNAME" ""' "$VERIFIED"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_DEFAULT_PASSWORD" ""' "$VERIFIED"
  [ "$status" -eq 0 ]
  run grep -F '/api/v1/users/register' "$VERIFIED"
  [ "$status" -eq 0 ]
  run grep -F '/api/v1/users/login' "$VERIFIED"
  [ "$status" -eq 0 ]
}

@test "healthcheck verifies stored Wazuh credentials without printing them" {
  run grep -F 'indexer-auth' "$HEALTH"
  [ "$status" -eq 0 ]
  run grep -F 'wazuh-api-auth' "$HEALTH"
  [ "$status" -eq 0 ]
}
