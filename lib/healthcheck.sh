#!/usr/bin/env bash
# shellcheck shell=bash

final_health() {
  phase "PHASE 6/7 - FINAL HEALTH CHECK"
  wait_wazuh_service "wazuh.indexer" 30 || die "Indexer lost health after Shuffle startup."
  wait_wazuh_service "wazuh.manager" 30 || die "Manager lost health after Shuffle startup."
  wait_wazuh_service "wazuh.dashboard" 30 || die "Dashboard lost health after Shuffle startup."
  local dash_code
  dash_code="$(curl -ksS -o /tmp/soclab-dashboard-final.out -w '%{http_code}' --max-time 10 "https://localhost:${WAZUH_DASHBOARD_PORT}/login" || true)"
  case "$dash_code" in
    200|301|302|401|403) ok "Final Wazuh dashboard HTTPS check passed (HTTP $dash_code)" ;;
    *) die "Final Wazuh dashboard HTTP check failed (HTTP ${dash_code:-none})." ;;
  esac
  if ! curl -fsS --max-time 10 "http://localhost:${SHUFFLE_FRONTEND_PORT}/" >/dev/null 2>&1 && ! curl -kfsS --max-time 10 "https://localhost:${SHUFFLE_HTTPS_PORT}/" >/dev/null 2>&1; then
    die "Final Shuffle frontend HTTP check failed."
  fi
  ok "All final service health checks passed"
}

print_report() {
  phase "PHASE 7/7 - INSTALLATION COMPLETE"
  echo; echo "WAZUH:"; (cd "$WAZUH_SINGLE" && docker compose ps -a)
  echo; echo "SHUFFLE:"; (cd "$SHUFFLE_DIR" && docker compose ps -a); echo
  cat <<EOF
============================================================
SOC LAB READY
============================================================
Wazuh version: ${WAZUH_VERSION}
Wazuh Dashboard: https://localhost:${WAZUH_DASHBOARD_PORT}
Wazuh Indexer:   https://localhost:9200
Wazuh API:       https://localhost:55000
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

  if [[ -f "$WAZUH_SINGLE/docker-compose.yml" ]]; then
    for svc in wazuh.indexer wazuh.manager wazuh.dashboard; do
      id="$(compose_service_id "$svc" || true)"
      if [[ -z "$id" ]]; then hc_fail "$svc" "container missing"; continue; fi
      h="$(compose_service_health "$svc")"
      if compose_service_running "$svc" && [[ "$h" == healthy || "$h" == none ]]; then
        hc_pass "$svc" "$(compose_service_name "$svc") health=$h"
      else
        hc_fail "$svc" "$(compose_service_name "$svc" || echo unknown) running=$(docker inspect -f '{{.State.Running}}' "$id" 2>/dev/null || echo unknown) health=$h"
      fi
    done
    id="$(compose_service_id wazuh.indexer || true)"
    if [[ -n "$id" ]] && docker exec "$id" sh -lc 'curl -fks https://localhost:9200/_plugins/_security/health | grep -q "\"status\":\"UP\""' >/dev/null 2>&1; then hc_pass "indexer-security" "OpenSearch Security status=UP"; else hc_fail "indexer-security" "Security health endpoint not UP"; fi
  else
    hc_fail "wazuh-compose" "$WAZUH_SINGLE/docker-compose.yml missing"
  fi

  code="$(curl -ksS -o /tmp/soclab-hc-dashboard.out -w '%{http_code}' --max-time 10 "https://localhost:${WAZUH_DASHBOARD_PORT}/login" || true)"
  if http_dashboard_ok "$code"; then hc_pass "dashboard-https" "HTTP $code on https://localhost:${WAZUH_DASHBOARD_PORT}/login"; else hc_fail "dashboard-https" "HTTP ${code:-none}"; fi

  code="$(curl -ksS -o /tmp/soclab-hc-indexer.out -w '%{http_code}' --max-time 10 https://localhost:9200/ || true)"
  if http_indexer_ok "$code"; then hc_pass "indexer-https" "HTTP $code on https://localhost:9200"; else hc_fail "indexer-https" "HTTP ${code:-none}"; fi

  code="$(curl -ksS -o /tmp/soclab-hc-api.out -w '%{http_code}' --max-time 10 https://localhost:55000/ || true)"
  if http_api_ok "$code"; then hc_pass "wazuh-api" "HTTP $code on https://localhost:55000"; else hc_fail "wazuh-api" "HTTP ${code:-none}"; fi

  if [[ -r "$STATE_DIR/credentials.txt" ]]; then
    local admin_user admin_pass api_user api_pass shuffle_os_pass
    admin_user="$(credential_value WAZUH_INDEXER_USERNAME || true)"; admin_pass="$(credential_value WAZUH_INDEXER_PASSWORD || true)"
    api_user="$(credential_value WAZUH_API_USERNAME || true)"; api_pass="$(credential_value WAZUH_API_PASSWORD || true)"
    shuffle_os_pass="$(credential_value SHUFFLE_OPENSEARCH_PASSWORD || true)"

    if [[ -n "$admin_user" && -n "$admin_pass" ]]; then
      code="$(curl -ksS -o /tmp/soclab-hc-indexer-auth.out -w '%{http_code}' --max-time 10 -u "${admin_user}:${admin_pass}" https://localhost:9200/ || true)"
      [[ "$code" == "200" ]] && hc_pass "indexer-auth" "stored credential authenticated" || hc_fail "indexer-auth" "HTTP ${code:-none}"
    else rows+=("SKIP|indexer-auth|credential fields missing"); fi

    if [[ -n "$api_user" && -n "$api_pass" ]]; then
      code="$(curl -ksS -o /tmp/soclab-hc-api-auth.out -w '%{http_code}' --max-time 10 -u "${api_user}:${api_pass}" -X POST 'https://localhost:55000/security/user/authenticate?raw=true' || true)"
      [[ "$code" == "200" ]] && hc_pass "wazuh-api-auth" "stored credential authenticated" || hc_fail "wazuh-api-auth" "HTTP ${code:-none}"
    else rows+=("SKIP|wazuh-api-auth|credential fields missing"); fi

    if [[ -n "$shuffle_os_pass" ]]; then
      code="$(curl -ksS -o /tmp/soclab-hc-shuffle-os-auth.out -w '%{http_code}' --max-time 10 -u "admin:${shuffle_os_pass}" "https://localhost:${SHUFFLE_OPENSEARCH_PORT}/" || true)"
      if [[ "$code" == "200" ]]; then
        hc_pass "shuffle-opensearch-auth" "stored credential authenticated over HTTPS"
      else
        code="$(curl -sS -o /tmp/soclab-hc-shuffle-os-auth.out -w '%{http_code}' --max-time 10 -u "admin:${shuffle_os_pass}" "http://localhost:${SHUFFLE_OPENSEARCH_PORT}/" || true)"
        [[ "$code" == "200" ]] && hc_pass "shuffle-opensearch-auth" "stored credential authenticated over HTTP" || rows+=("SKIP|shuffle-opensearch-auth|endpoint not directly available/authenticated")
      fi
    else rows+=("SKIP|shuffle-opensearch-auth|credential field missing"); fi
    unset admin_user admin_pass api_user api_pass shuffle_os_pass
  else
    rows+=("SKIP|credential-auth|$STATE_DIR/credentials.txt is not readable")
  fi

  if curl -fsS --max-time 10 "http://localhost:${SHUFFLE_FRONTEND_PORT}/" >/dev/null 2>&1; then hc_pass "shuffle-frontend" "HTTP reachable on http://localhost:${SHUFFLE_FRONTEND_PORT}"; elif curl -kfsS --max-time 10 "https://localhost:${SHUFFLE_HTTPS_PORT}/" >/dev/null 2>&1; then hc_pass "shuffle-frontend" "HTTPS reachable on https://localhost:${SHUFFLE_HTTPS_PORT}"; else hc_fail "shuffle-frontend" "frontend not reachable on ${SHUFFLE_FRONTEND_PORT}/${SHUFFLE_HTTPS_PORT}"; fi

  printf '\n%-6s  %-22s  %s\n' STATUS COMPONENT DETAILS
  printf '%-6s  %-22s  %s\n' '------' '----------------------' '-------'
  local row status component details
  for row in "${rows[@]}"; do IFS='|' read -r status component details <<<"$row"; printf '%-6s  %-22s  %s\n' "$status" "$component" "$details"; done
  echo
  if (( failures == 0 )); then ok "SOC lab healthcheck PASSED"; return 0; fi
  warn "SOC lab healthcheck FAILED: ${failures} check(s) failed"; return 1
}

status_all() {
  check_docker
  echo "Wazuh version target: $WAZUH_VERSION"; echo
  if [[ -f "$WAZUH_SINGLE/docker-compose.yml" ]]; then echo "WAZUH:"; (cd "$WAZUH_SINGLE" && docker compose ps -a) || true; else echo "WAZUH: not installed at $WAZUH_SINGLE"; fi
  echo
  if [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]]; then echo "SHUFFLE:"; (cd "$SHUFFLE_DIR" && docker compose ps -a) || true; else echo "SHUFFLE: not installed at $SHUFFLE_DIR"; fi
  echo; echo "URLs:"; echo "  Wazuh Dashboard: https://localhost:${WAZUH_DASHBOARD_PORT}"; echo "  Wazuh Indexer:   https://localhost:9200"; echo "  Wazuh API:       https://localhost:55000"; echo "  Shuffle:         http://localhost:${SHUFFLE_FRONTEND_PORT}"
  [[ -f "$STATE_DIR/credentials.txt" ]] && echo "  Credentials:     $STATE_DIR/credentials.txt"
}

logs_cmd() {
  check_docker
  local target="${1:-all}"
  case "$target" in wazuh|all) if [[ -f "$WAZUH_SINGLE/docker-compose.yml" ]]; then (cd "$WAZUH_SINGLE" && docker compose logs --tail 300); else warn "Wazuh Compose tree not found"; fi ;; esac
  case "$target" in shuffle|all) if [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]]; then (cd "$SHUFFLE_DIR" && docker compose logs --tail 300); else warn "Shuffle Compose tree not found"; fi ;; esac
  case "$target" in wazuh|shuffle|all) ;; *) die "Unknown logs target '$target'. Use wazuh, shuffle, or all." ;; esac
}

reset_cmd() { need_root; check_docker; phase "RESET SOC LAB"; clean_lab; ok "SOC lab reset complete"; }

credentials_cmd() {
  local file="$STATE_DIR/credentials.txt"
  [[ -f "$file" ]] || die "Credential inventory not found: $file"
  echo "Local credential inventory: $file"
  echo "Permissions: $(stat -c '%A %U:%G' "$file" 2>/dev/null || echo unknown)"
  echo "This command does not print secret values. To display them explicitly: cat '$file'"
}
