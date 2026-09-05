#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
}

@test "installer is valid bash" {
  run bash -n "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "Wazuh beta5 is pinned" {
  run grep -F 'WAZUH_VERSION="5.0.0-beta5"' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "installer does not contain destructive global docker prune commands" {
  run bash -c "grep -Ev '^[[:space:]]*#' '$INSTALL' | grep -E 'docker[[:space:]]+(system|volume|image)[[:space:]]+prune'"
  [ "$status" -ne 0 ]
}

@test "container discovery uses docker compose service IDs" {
  run grep -F 'docker compose ps -q --all "$service"' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "beta5 UID and GID are detected from actual images" {
  run grep -F 'detect_wazuh_image_accounts' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'beta5 indexer user:' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "certificate mount preflight is mandatory" {
  run grep -F 'verify_wazuh_cert_mounts' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'Certificate mount/readability preflight failed' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "dashboard authenticated HTTP responses count as liveness" {
  run bash -c "source '$INSTALL'; http_dashboard_ok 401"
  [ "$status" -eq 0 ]
  run bash -c "source '$INSTALL'; http_dashboard_ok 403"
  [ "$status" -eq 0 ]
  run bash -c "source '$INSTALL'; http_dashboard_ok 500"
  [ "$status" -ne 0 ]
}

@test "indexer and API HTTP policies are explicit" {
  run bash -c "source '$INSTALL'; http_indexer_ok 401 && http_api_ok 404"
  [ "$status" -eq 0 ]
}
