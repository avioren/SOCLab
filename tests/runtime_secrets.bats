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
  run grep -R -E 'capture_wazuh_stock_credentials|configure_wazuh_runtime_credentials|rotate_wazuh_runtime_credentials|verify_runtime_credentials|verify_live_user_credentials|wazuh-passwords-tool\.sh|internal_users\.yml' "$INSTALL"
  [ "$status" -ne 0 ]
}

@test "credential inventory is local and mode 600" {
  run grep -F 'STATE_DIR="$ROOT_DIR/state"' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'chmod 600 "$STATE_DIR/credentials.txt"' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "credential inventory uses Wazuh 5 beta dashboard and indexer defaults" {
  run grep -F 'WAZUH_DASHBOARD_USERNAME=admin' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'WAZUH_DASHBOARD_PASSWORD=admin' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'WAZUH_INDEXER_USERNAME=admin' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'WAZUH_INDEXER_PASSWORD=admin' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "credential inventory records Wazuh API defaults" {
  run grep -F 'WAZUH_API_USERNAME=wazuh' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'WAZUH_API_PASSWORD=wazuh' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'WAZUH_WUI_API_USERNAME=wazuh-wui' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'WAZUH_WUI_API_PASSWORD=wazuh-wui' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "credential inventory records dashboard service account" {
  run grep -F 'WAZUH_DASHBOARD_SERVICE_USERNAME=kibanaserver' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'WAZUH_DASHBOARD_SERVICE_PASSWORD=kibanaserver' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "Shuffle bootstrap values are generated locally and OpenSearch password is strong" {
  run grep -F 'generate_shuffle_opensearch_password' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'secrets.SystemRandom().shuffle(chars)' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_DEFAULT_USERNAME" "admin@soclab.local"' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_DEFAULT_PASSWORD" "$shuffle_pw"' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_UI_USERNAME=admin@soclab.local' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_UI_PASSWORD=${shuffle_pw}' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "Shuffle secrets are never rendered by compose validation" {
  run grep -F 'docker compose config --quiet' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -E 'docker compose config[[:space:]]*>' "$SHUFFLE"
  [ "$status" -ne 0 ]
}

@test "healthcheck checks authenticated Shuffle datastore when local inventory exists" {
  run grep -F 'SHUFFLE_OPENSEARCH_PASSWORD' "$HEALTH"
  [ "$status" -eq 0 ]
  run grep -F 'verify_shuffle_opensearch' "$HEALTH"
  [ "$status" -eq 0 ]
}

@test "healthcheck still checks Wazuh listeners" {
  run grep -F 'dashboard-https' "$HEALTH"
  [ "$status" -eq 0 ]
  run grep -F 'wazuh-api' "$HEALTH"
  [ "$status" -eq 0 ]
}
