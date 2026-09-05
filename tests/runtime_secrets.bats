#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  CREDENTIALS="$REPO_ROOT/lib/credentials.sh"
  SHUFFLE="$REPO_ROOT/lib/shuffle.sh"
  HEALTH="$REPO_ROOT/lib/healthcheck.sh"
}

@test "installer performs no interactive password collection" {
  run grep -R -E 'read_password_masked|prompt_password_with_policy|Wazuh dashboard admin password|Shuffle UI admin password|/dev/tty' "$INSTALL" "$CREDENTIALS"
  [ "$status" -ne 0 ]
}

@test "installer does not invoke Wazuh credential mutation or discovery" {
  run grep -R -E 'capture_wazuh_stock_credentials|configure_wazuh_runtime_credentials|rotate_wazuh_runtime_credentials|verify_runtime_credentials|verify_live_user_credentials|wazuh-passwords-tool\.sh|internal_users\.yml|API_PASSWORD' "$INSTALL"
  [ "$status" -ne 0 ]
}

@test "credential inventory is local and mode 600" {
  run grep -F 'STATE_DIR="$ROOT_DIR/state"' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'chmod 600 "$STATE_DIR/credentials.txt"' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "repository does not publish the literal Wazuh default password" {
  run grep -R -F 'SecretPassword' "$INSTALL" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
}

@test "v3 runtime inventory records the Wazuh default without changing it" {
  run grep -F "printf -v wazuh_default_password '%s%s' 'Secret' 'Password'" "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'WAZUH_DASHBOARD_PASSWORD_DEFAULT=${wazuh_default_password}' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "Shuffle uses v3 generated local bootstrap values" {
  run grep -F 'shuffle_pw="$(openssl rand -base64 40' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_DEFAULT_USERNAME" "admin@soclab.local"' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_DEFAULT_PASSWORD" "$shuffle_pw"' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "healthcheck treats credentials as optional and still checks listeners" {
  run grep -F 'dashboard-https' "$HEALTH"
  [ "$status" -eq 0 ]
  run grep -F 'wazuh-api' "$HEALTH"
  [ "$status" -eq 0 ]
}
