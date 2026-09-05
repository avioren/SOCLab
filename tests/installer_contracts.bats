#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  WAZUH="$REPO_ROOT/lib/wazuh.sh"
  HEALTH="$REPO_ROOT/lib/healthcheck.sh"
}

@test "installer and libraries are valid bash" {
  run bash -c "bash -n '$INSTALL' && for f in '$REPO_ROOT'/lib/*.sh; do bash -n \"\$f\" || exit 1; done"
  [ "$status" -eq 0 ]
}

@test "Wazuh beta5 is pinned" {
  run grep -F 'WAZUH_VERSION="5.0.0-beta5"' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "project does not contain destructive global docker prune commands" {
  run bash -c "grep -REv '^[[:space:]]*#' '$INSTALL' '$REPO_ROOT/lib' | grep -E 'docker[[:space:]]+(system|volume|image)[[:space:]]+prune'"
  [ "$status" -ne 0 ]
}

@test "container discovery uses docker compose service IDs" {
  run grep -F 'docker compose ps -q --all "$service"' "$WAZUH"
  [ "$status" -eq 0 ]
}

@test "beta5 UID and GID are detected from actual images" {
  run grep -F 'detect_wazuh_image_accounts' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'beta5 indexer user:' "$WAZUH"
  [ "$status" -eq 0 ]
}

@test "certificate mount preflight is mandatory" {
  run grep -F 'verify_wazuh_cert_mounts' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'Certificate mount/readability preflight failed' "$WAZUH"
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
