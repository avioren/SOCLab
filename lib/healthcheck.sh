#!/usr/bin/env bash
# shellcheck shell=bash

shuffle_runtime_health() {
  # Usage: shuffle_runtime_health <pass_fn> <fail_fn> <skip_fn>
  local pass_fn="$1" fail_fn="$2" skip_fn="$3"
  local state control nodes availability core driver scope attachable code os_pass
  local id running image replicas mounts net_id

  state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo unknown)"
  control="$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || echo false)"
  if [[ "$state" == "active" && "$control" == "true" ]] && docker node ls >/dev/null 2>&1; then
    nodes="$(docker node ls -q | wc -l | tr -d ' ')"
    availability="$(docker node inspect self --format '{{.Spec.Availability}}' 2>/dev/null || echo unknown)"
    if [[ "$nodes" == "1" && "$availability" == "active" ]]; then
      "$pass_fn" "shuffle-swarm" "single manager+worker node active"
    else
      "$fail_fn" "shuffle-swarm" "nodes=$nodes availability=$availability; expected one active node"
    fi
  else
    "$fail_fn" "shuffle-swarm" "state=$state manager=$control"
  fi

  if docker network inspect ingress >/dev/null 2>&1 &&
     [[ "$(docker network inspect -f '{{.Driver}}' ingress 2>/dev/null || true)" == "overlay" ]]; then
    "$pass_fn" "swarm-ingress" "overlay present"
  else
    "$fail_fn" "swarm-ingress" "missing or not overlay"
  fi

  core="$(shuffle_core_network_name)"
  for net in "$core" "$SHUFFLE_SWARM_NETWORK_NAME"; do
    if ! docker network inspect "$net" >/dev/null 2>&1; then
      "$fail_fn" "network:$net" "missing"
      continue
    fi
    driver="$(docker network inspect -f '{{.Driver}}' "$net" 2>/dev/null || echo unknown)"
    scope="$(docker network inspect -f '{{.Scope}}' "$net" 2>/dev/null || echo unknown)"
    attachable="$(docker network inspect -f '{{.Attachable}}' "$net" 2>/dev/null || echo false)"
    if [[ "$driver" == "overlay" && "$scope" == "swarm" && "$attachable" == "true" ]]; then
      "$pass_fn" "network:$net" "overlay/swarm/attachable"
    else
      "$fail_fn" "network:$net" "driver=$driver scope=$scope attachable=$attachable"
    fi
  done

  for c in shuffle-frontend shuffle-backend shuffle-orborus shuffle-opensearch; do
    if docker inspect "$c" >/dev/null 2>&1; then
      running="$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null || echo false)"
      image="$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null || echo unknown)"
      if [[ "$running" == "true" ]]; then
        "$pass_fn" "$c" "running image=$image"
      else
        "$fail_fn" "$c" "not running image=$image"
      fi
    else
      "$fail_fn" "$c" "container missing"
    fi
  done

  if docker inspect shuffle-backend >/dev/null 2>&1 &&
     docker inspect -f '{{json .NetworkSettings.Networks}}' shuffle-backend 2>/dev/null |
       grep -q "\"${SHUFFLE_SWARM_NETWORK_NAME}\""; then
    "$pass_fn" "backend-exec-net" "attached to $SHUFFLE_SWARM_NETWORK_NAME"
  else
    "$fail_fn" "backend-exec-net" "backend not attached to execution overlay"
  fi

  if docker inspect shuffle-orborus >/dev/null 2>&1 &&
     docker inspect -f '{{json .NetworkSettings.Networks}}' shuffle-orborus 2>/dev/null |
       grep -q "\"${SHUFFLE_SWARM_NETWORK_NAME}\""; then
    "$pass_fn" "orborus-exec-net" "attached to $SHUFFLE_SWARM_NETWORK_NAME"
  else
    "$fail_fn" "orborus-exec-net" "Orborus not attached to execution overlay"
  fi

  code="$(curl -sS -o /tmp/soclab-hc-shuffle-checkusers.out -w '%{http_code}' --max-time 15 \
    "http://localhost:${SHUFFLE_BACKEND_PORT}/api/v1/checkusers" || true)"
  if [[ "$code" == "200" ]]; then
    "$pass_fn" "shuffle-backend-db" "/api/v1/checkusers HTTP 200"
  else
    "$fail_fn" "shuffle-backend-db" "/api/v1/checkusers HTTP ${code:-none}"
  fi

  if curl -fsS --max-time 10 "http://localhost:${SHUFFLE_FRONTEND_PORT}/" >/dev/null 2>&1; then
    "$pass_fn" "shuffle-frontend" "HTTP reachable on http://localhost:${SHUFFLE_FRONTEND_PORT}"
  elif curl -kfsS --max-time 10 "https://localhost:${SHUFFLE_HTTPS_PORT}/" >/dev/null 2>&1; then
    "$pass_fn" "shuffle-frontend" "HTTPS reachable on https://localhost:${SHUFFLE_HTTPS_PORT}"
  else
    "$fail_fn" "shuffle-frontend" "frontend not reachable on ${SHUFFLE_FRONTEND_PORT}/${SHUFFLE_HTTPS_PORT}"
  fi

  os_pass="$(credential_value SHUFFLE_OPENSEARCH_PASSWORD || true)"
  if [[ -n "$os_pass" ]]; then
    if verify_shuffle_opensearch "$os_pass"; then
      "$pass_fn" "shuffle-opensearch" "authenticated cluster health green/yellow"
    else
      "$fail_fn" "shuffle-opensearch" "authenticated cluster health failed"
    fi
  else
    "$skip_fn" "shuffle-opensearch" "credential inventory unavailable; direct auth test skipped"
  fi

  if docker service inspect shuffle-workers >/dev/null 2>&1; then
    replicas="$(docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null | awk '$1 == "shuffle-workers" {print $2; exit}')"
    image="$(docker service inspect -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' shuffle-workers 2>/dev/null || true)"
    net_id="$(docker network inspect -f '{{.Id}}' "$SHUFFLE_SWARM_NETWORK_NAME" 2>/dev/null || true)"
    mounts="$(docker service inspect -f '{{json .Spec.TaskTemplate.ContainerSpec.Mounts}}' shuffle-workers 2>/dev/null || true)"

    if [[ "$replicas" == "1/1" ]]; then
      "$pass_fn" "shuffle-workers" "replicas=$replicas"
    else
      "$fail_fn" "shuffle-workers" "replicas=${replicas:-unknown}"
    fi

    if [[ "$image" == "$SHUFFLE_WORKER_IMAGE"* ]]; then
      "$pass_fn" "worker-image" "$SHUFFLE_WORKER_IMAGE"
    else
      "$fail_fn" "worker-image" "actual=$image expected=$SHUFFLE_WORKER_IMAGE"
    fi

    if [[ -n "$net_id" ]] &&
       docker service inspect -f '{{range .Spec.TaskTemplate.Networks}}{{println .Target}}{{end}}' shuffle-workers 2>/dev/null |
         grep -qx "$net_id"; then
      "$pass_fn" "worker-exec-net" "$SHUFFLE_SWARM_NETWORK_NAME"
    else
      "$fail_fn" "worker-exec-net" "worker not attached to execution overlay"
    fi

    if [[ "$mounts" == *"/var/run/docker.sock"* ]]; then
      "$pass_fn" "worker-docker-api" "manager socket mounted"
    else
      "$fail_fn" "worker-docker-api" "manager Docker socket not mounted"
    fi
  else
    "$fail_fn" "shuffle-workers" "Swarm worker service missing"
  fi

  if docker inspect shuffle-orborus >/dev/null 2>&1; then
    if docker logs --since 10m shuffle-orborus 2>&1 |
       grep -Eqi 'network shuffle_swarm_executions not found|failed to set up container networking'; then
      "$fail_fn" "orborus-network" "recent execution-network errors found"
    else
      "$pass_fn" "orborus-network" "no recent missing-network/container-networking errors"
    fi
  fi

  if docker inspect shuffle-backend >/dev/null 2>&1; then
    if docker logs --since 10m shuffle-backend 2>&1 |
       grep -Eqi 'No mapping found for \[updated_at\]|search_phase_execution_exception.*all shards failed'; then
      "$fail_fn" "shuffle-db-schema" "recent OpenSearch mapping/shard errors found in backend logs"
    else
      "$pass_fn" "shuffle-db-schema" "no recent notification mapping/all-shards-failed errors"
    fi
  fi
}

final_health() {
  phase "PHASE 6/7 - FINAL HEALTH CHECK"

  wait_wazuh_service "wazuh.indexer" 30 || die "Indexer lost health after Shuffle startup."
  wait_wazuh_service "wazuh.manager" 30 || die "Manager lost health after Shuffle startup."
  wait_wazuh_service "wazuh.dashboard" 30 || die "Dashboard lost health after Shuffle startup."
  verify_wazuh_api_runtime_configuration

  local dash_code
  dash_code="$(curl -ksS -o /tmp/soclab-dashboard-final.out -w '%{http_code}' --max-time 10 \
    "https://localhost:${WAZUH_DASHBOARD_PORT}/login" || true)"
  case "$dash_code" in
    200|301|302|401|403) ok "Final Wazuh dashboard HTTPS check passed (HTTP $dash_code)" ;;
    *) die "Final Wazuh dashboard HTTP check failed (HTTP ${dash_code:-none})." ;;
  esac

  local failures=0
  sh_final_pass() { ok "$1: $2"; }
  sh_final_fail() { warn "$1: $2"; failures=$((failures + 1)); }
  sh_final_skip() { warn "$1: SKIP - $2"; }
  shuffle_runtime_health sh_final_pass sh_final_fail sh_final_skip

  (( failures == 0 )) || {
    dump_shuffle_diagnostics
    die "Final Shuffle Swarm health gate failed with $failures problem(s)."
  }

  ok "All final Wazuh + Shuffle Swarm service health checks passed"
}

print_report() {
  phase "PHASE 7/7 - INSTALLATION COMPLETE"
  echo
  echo "WAZUH:"
  (cd "$WAZUH_SINGLE" && docker compose ps -a)
  echo
  echo "SHUFFLE CORE:"
  (cd "$SHUFFLE_DIR" && docker compose ps -a)
  echo
  echo "SHUFFLE SWARM:"
  docker node ls
  docker service ls
  echo

  cat <<EOF
============================================================
SOC LAB READY
============================================================
Wazuh version:   ${WAZUH_VERSION}
Shuffle version: ${SHUFFLE_VERSION}
Shuffle runtime: single-node Docker Swarm
Execution net:   ${SHUFFLE_SWARM_NETWORK_NAME}

Wazuh Dashboard: https://localhost:${WAZUH_DASHBOARD_PORT}
Wazuh Indexer:   https://localhost:9200
Wazuh API:       https://localhost:${WAZUH_API_PORT}
Shuffle:         http://localhost:${SHUFFLE_FRONTEND_PORT}

Credentials:     ${STATE_DIR}/credentials.txt
Installer log:   ${LOG}
Wazuh source:    ${WAZUH_DIR}
Shuffle source:  ${SHUFFLE_DIR}
============================================================
EOF
}

http_dashboard_ok() { case "${1:-}" in 200|301|302|401|403) return 0 ;; *) return 1 ;; esac; }
http_indexer_ok() { case "${1:-}" in 200|401|403) return 0 ;; *) return 1 ;; esac; }
http_api_ok() { case "${1:-}" in 200|401|403|404) return 0 ;; *) return 1 ;; esac; }

healthcheck_all() {
  check_docker
  local failures=0 code id h
  local -a rows=()

  hc_pass() { rows+=("PASS|$1|$2"); }
  hc_fail() { rows+=("FAIL|$1|$2"); failures=$((failures + 1)); }
  hc_skip() { rows+=("SKIP|$1|$2"); }

  if [[ -f "$WAZUH_SINGLE/docker-compose.yml" ]]; then
    for svc in wazuh.indexer wazuh.manager wazuh.dashboard; do
      id="$(compose_service_id "$svc" || true)"
      if [[ -z "$id" ]]; then
        hc_fail "$svc" "container missing"
        continue
      fi
      h="$(compose_service_health "$svc")"
      if compose_service_running "$svc" && [[ "$h" == healthy || "$h" == none ]]; then
        hc_pass "$svc" "$(compose_service_name "$svc") health=$h"
      else
        hc_fail "$svc" "$(compose_service_name "$svc" || echo unknown) running=$(docker inspect -f '{{.State.Running}}' "$id" 2>/dev/null || echo unknown) health=$h"
      fi
    done

    id="$(compose_service_id wazuh.indexer || true)"
    if [[ -n "$id" ]] && docker exec "$id" sh -lc \
      'curl -fks https://localhost:9200/_plugins/_security/health | grep -q "\"status\":\"UP\""' \
      >/dev/null 2>&1; then
      hc_pass "indexer-security" "OpenSearch Security status=UP"
    else
      hc_fail "indexer-security" "Security health endpoint not UP"
    fi
  else
    hc_fail "wazuh-compose" "$WAZUH_SINGLE/docker-compose.yml missing"
  fi

  code="$(curl -ksS -o /tmp/soclab-hc-dashboard.out -w '%{http_code}' --max-time 10 \
    "https://localhost:${WAZUH_DASHBOARD_PORT}/login" || true)"
  if http_dashboard_ok "$code"; then
    hc_pass "dashboard-https" "HTTP $code on https://localhost:${WAZUH_DASHBOARD_PORT}/login"
  else
    hc_fail "dashboard-https" "HTTP ${code:-none}"
  fi

  code="$(curl -ksS -o /tmp/soclab-hc-indexer.out -w '%{http_code}' --max-time 10 \
    https://localhost:9200/ || true)"
  if http_indexer_ok "$code"; then
    hc_pass "indexer-https" "HTTP $code on https://localhost:9200"
  else
    hc_fail "indexer-https" "HTTP ${code:-none}"
  fi

  code="$(curl -ksS -o /tmp/soclab-hc-api.out -w '%{http_code}' --max-time 10 \
    "https://localhost:${WAZUH_API_PORT}/" || true)"
  if http_api_ok "$code"; then
    hc_pass "wazuh-api" "HTTP $code on https://localhost:${WAZUH_API_PORT}"
  else
    hc_fail "wazuh-api" "HTTP ${code:-none}"
  fi

  if [[ -r "$STATE_DIR/credentials.txt" ]]; then
    local admin_user admin_pass api_user api_pass
    admin_user="$(credential_value WAZUH_INDEXER_USERNAME || true)"
    admin_pass="$(credential_value WAZUH_INDEXER_PASSWORD || true)"
    api_user="$(credential_value WAZUH_API_USERNAME || true)"
    api_pass="$(credential_value WAZUH_API_PASSWORD || true)"

    if [[ -n "$admin_user" && -n "$admin_pass" ]]; then
      code="$(curl -ksS -o /tmp/soclab-hc-indexer-auth.out -w '%{http_code}' --max-time 10 \
        -u "${admin_user}:${admin_pass}" https://localhost:9200/ || true)"
      [[ "$code" == "200" ]] && hc_pass "indexer-auth" "stored credential authenticated" ||
        hc_fail "indexer-auth" "HTTP ${code:-none}"
    else
      hc_skip "indexer-auth" "credential fields missing"
    fi

    if [[ -n "$api_user" && -n "$api_pass" ]]; then
      code="$(curl -ksS -o /tmp/soclab-hc-api-auth.out -w '%{http_code}' --max-time 10 \
        -u "${api_user}:${api_pass}" -X POST "https://localhost:${WAZUH_API_PORT}/security/user/authenticate?raw=true" || true)"
      [[ "$code" == "200" ]] && hc_pass "wazuh-api-auth" "stored credential authenticated" ||
        hc_fail "wazuh-api-auth" "HTTP ${code:-none}"
    else
      hc_skip "wazuh-api-auth" "credential fields missing"
    fi
  else
    hc_skip "credential-auth" "$STATE_DIR/credentials.txt is not readable"
  fi

  if [[ -f "$WAZUH_SINGLE/docker-compose.yml" ]]; then
    if verify_wazuh_api_runtime_configuration >/dev/null 2>&1; then
      hc_pass "wazuh-api-config" "manager and dashboard both use TCP/${WAZUH_API_PORT}"
    else
      hc_fail "wazuh-api-config" "manager/dashboard API configuration mismatch"
    fi
  fi

  shuffle_runtime_health hc_pass hc_fail hc_skip

  printf '\n%-6s  %-26s  %s\n' STATUS COMPONENT DETAILS
  printf '%-6s  %-26s  %s\n' '------' '--------------------------' '-------'
  local row status component details
  for row in "${rows[@]}"; do
    IFS='|' read -r status component details <<<"$row"
    printf '%-6s  %-26s  %s\n' "$status" "$component" "$details"
  done

  echo
  if (( failures == 0 )); then
    ok "SOC lab healthcheck PASSED"
    return 0
  fi
  warn "SOC lab healthcheck FAILED: ${failures} check(s) failed"
  return 1
}

status_all() {
  check_docker
  echo "Wazuh version target:   $WAZUH_VERSION"
  echo "Shuffle version target: $SHUFFLE_VERSION"
  echo

  if [[ -f "$WAZUH_SINGLE/docker-compose.yml" ]]; then
    echo "WAZUH:"
    (cd "$WAZUH_SINGLE" && docker compose ps -a) || true
  else
    echo "WAZUH: not installed at $WAZUH_SINGLE"
  fi

  echo
  if [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]]; then
    echo "SHUFFLE CORE:"
    (cd "$SHUFFLE_DIR" && docker compose ps -a) || true
  else
    echo "SHUFFLE: not installed at $SHUFFLE_DIR"
  fi

  echo
  echo "SWARM:"
  docker info --format '  state={{.Swarm.LocalNodeState}} manager={{.Swarm.ControlAvailable}}' 2>/dev/null || true
  docker node ls 2>/dev/null || true

  echo
  echo "SHUFFLE SWARM SERVICES:"
  docker service ls --filter name=shuffle 2>/dev/null || true

  echo
  echo "OVERLAY NETWORKS:"
  docker network ls --filter driver=overlay 2>/dev/null || true

  echo
  echo "URLs:"
  echo "  Wazuh Dashboard: https://localhost:${WAZUH_DASHBOARD_PORT}"
  echo "  Wazuh Indexer:   https://localhost:9200"
  echo "  Wazuh API:       https://localhost:${WAZUH_API_PORT}"
  echo "  Shuffle:         http://localhost:${SHUFFLE_FRONTEND_PORT}"
  [[ -f "$STATE_DIR/credentials.txt" ]] && echo "  Credentials:     $STATE_DIR/credentials.txt"
}

logs_cmd() {
  check_docker
  local target="${1:-all}"

  case "$target" in
    wazuh|all)
      if [[ -f "$WAZUH_SINGLE/docker-compose.yml" ]]; then
        (cd "$WAZUH_SINGLE" && docker compose logs --tail 300)
      else
        warn "Wazuh Compose tree not found"
      fi
      ;;
  esac

  case "$target" in
    shuffle|all)
      if [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]]; then
        (cd "$SHUFFLE_DIR" && docker compose logs --tail 300)
      else
        warn "Shuffle Compose tree not found"
      fi
      if docker service inspect shuffle-workers >/dev/null 2>&1; then
        echo "===== shuffle-workers service ====="
        docker service ps --no-trunc shuffle-workers || true
        docker service logs --tail 200 shuffle-workers 2>/dev/null || true
      fi
      ;;
  esac

  case "$target" in
    wazuh|shuffle|all) ;;
    *) die "Unknown logs target '$target'. Use wazuh, shuffle, or all." ;;
  esac
}

reset_cmd() {
  need_root
  check_docker
  phase "RESET SOC LAB"
  cleanup_shuffle_swarm_runtime
  clean_lab
  ok "SOCLab reset complete; Docker Swarm mode itself was intentionally left unchanged"
}

credentials_cmd() {
  local file="$STATE_DIR/credentials.txt"
  [[ -f "$file" ]] || die "Credential inventory not found: $file"
  echo "Local credential inventory: $file"
  echo "Permissions: $(stat -c '%A %U:%G' "$file" 2>/dev/null || echo unknown)"
  echo "This command does not print secret values. To display them explicitly: cat '$file'"
}
