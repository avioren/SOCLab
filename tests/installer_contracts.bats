#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  COMMON="$REPO_ROOT/lib/common.sh"
  SHUFFLE="$REPO_ROOT/lib/shuffle.sh"
  HEALTH="$REPO_ROOT/lib/healthcheck.sh"
  WAZUH="$REPO_ROOT/lib/wazuh.sh"
  V3_CERTS="$REPO_ROOT/lib/wazuh_v3_certs.sh"
}

@test "installer is valid bash" {
  run bash -n "$INSTALL"
  [ "$status" -eq 0 ]
  run bash -n "$COMMON" "$SHUFFLE" "$HEALTH"
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

@test "installer pins stable Shuffle release and all execution images" {
  run grep -F 'SHUFFLE_VERSION="${SHUFFLE_VERSION:-2.2.1}"' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'shuffle-frontend:${SHUFFLE_VERSION}' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'shuffle-backend:${SHUFFLE_VERSION}' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'shuffle-orborus:${SHUFFLE_VERSION}' "$INSTALL"
  [ "$status" -eq 0 ]
  run grep -F 'shuffle-worker:${SHUFFLE_VERSION}' "$INSTALL"
  [ "$status" -eq 0 ]
}

@test "installer does not contain executable global Docker prune commands" {
  run grep -RE '^[[:space:]]*docker[[:space:]]+(system|volume|image)[[:space:]]+prune' "$INSTALL" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
}

@test "cleanup never leaves the global swarm by force" {
  run grep -RE '^[[:space:]]*docker[[:space:]]+swarm[[:space:]]+leave' "$INSTALL" "$REPO_ROOT/lib"
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

@test "Shuffle Swarm prerequisites initialize a manager and execution overlay" {
  run grep -F 'docker swarm init' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F -- '--driver overlay' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F -- '--attachable' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_SWARM_NETWORK_NAME' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "host prerequisites enable IPv4 forwarding for Swarm networking" {
  run grep -F 'net.ipv4.ip_forward=1' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'sysctl -w net.ipv4.ip_forward=1' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "Shuffle OpenSearch data ownership is discovered from the pinned image" {
  run grep -F 'detect_shuffle_opensearch_image_account' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'id -u opensearch' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'chown -R "${SHUFFLE_OPENSEARCH_UID}:${SHUFFLE_OPENSEARCH_GID}"' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "Shuffle OpenSearch password generator guarantees required character classes" {
  run grep -F 'secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ")' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'secrets.choice("abcdefghijkmnopqrstuvwxyz")' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'secrets.choice("23456789")' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'secrets.choice("!@%_-")' "$SHUFFLE"
  [ "$status" -eq 0 ]
}

@test "Shuffle Compose validation does not render secrets into a temp file" {
  run grep -F 'docker compose config --quiet' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -E 'docker compose config[[:space:]]*>' "$SHUFFLE"
  [ "$status" -ne 0 ]
}

@test "Shuffle healthcheck validates the execution plane, not only the frontend" {
  run grep -F 'shuffle-workers' "$HEALTH"
  [ "$status" -eq 0 ]
  run grep -F 'shuffle_swarm_executions' "$HEALTH"
  [ "$status" -eq 0 ]
  run grep -F '/api/v1/checkusers' "$HEALTH"
  [ "$status" -eq 0 ]
  run grep -F '/var/run/docker.sock' "$HEALTH"
  [ "$status" -eq 0 ]
}

@test "cleanup removes lab-owned worker services and overlay without destroying Swarm" {
  run grep -F 'cleanup_shuffle_swarm_runtime' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'docker service rm shuffle-workers' "$SHUFFLE"
  [ "$status" -eq 0 ]
  run grep -F 'docker network rm "$SHUFFLE_SWARM_NETWORK_NAME"' "$SHUFFLE"
  [ "$status" -eq 0 ]
}
