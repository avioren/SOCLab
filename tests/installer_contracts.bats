#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  WAZUH="$REPO_ROOT/lib/wazuh.sh"
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

@test "Wazuh beta5 password hashing uses bundled JDK and supported hash argument" {
  run grep -F 'export JAVA_HOME=/usr/share/wazuh-indexer/jdk' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'bash "$tool" -p "$password"' "$WAZUH"
  [ "$status" -eq 0 ]
}

@test "plaintext Wazuh password is fed to disposable hash container on stdin" {
  run grep -F 'printf '\''%s\n'\'' "$password" |' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'docker run --rm -i --entrypoint bash' "$WAZUH"
  [ "$status" -eq 0 ]
}

@test "Wazuh hash failures emit sanitized actionable diagnostics" {
  run grep -F 'The plaintext password was not logged.' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'no bcrypt hash was found in its output' "$WAZUH"
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
