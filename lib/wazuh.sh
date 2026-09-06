#!/usr/bin/env bash
# shellcheck shell=bash

# Shuffle's built-in Tenzir/Sigma runtime publishes host TCP/1514. Keep Wazuh
# listening on its normal container port 1514, but publish it on a distinct
# host port so both products can coexist on the same Docker Desktop daemon.
WAZUH_AGENT_PORT="${WAZUH_AGENT_PORT:-15140}"

patch_wazuh_dashboard_port() {
  local compose="$WAZUH_SINGLE/docker-compose.yml"
  python3 - "$compose" "$WAZUH_DASHBOARD_PORT" "$WAZUH_AGENT_PORT" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
dashboard_port = sys.argv[2]
agent_port = sys.argv[3]
text = p.read_text()

# Dashboard host mapping: host WAZUH_DASHBOARD_PORT -> container 5601.
before = text
text = re.sub(r'(?m)^(\s*-\s*)"?443:5601"?\s*$', rf'\1"{dashboard_port}:5601"', text)
text = re.sub(r'(?m)^(\s*-\s*)"?0\.0\.0\.0:443:5601"?\s*$', rf'\1"0.0.0.0:{dashboard_port}:5601"', text)
if text == before and f"{dashboard_port}:5601" not in text:
    raise SystemExit("Could not locate dashboard host port mapping 443:5601")

# Wazuh agent traffic remains container TCP/1514, but host TCP/1514 is
# reserved for Shuffle/Tenzir in this single-host lab.
before_agent = text
text = re.sub(r'(?m)^(\s*-\s*)"?1514:1514"?\s*$', rf'\1"{agent_port}:1514"', text)
text = re.sub(r'(?m)^(\s*-\s*)"?0\.0\.0\.0:1514:1514"?\s*$', rf'\1"0.0.0.0:{agent_port}:1514"', text)
if text == before_agent and f"{agent_port}:1514" not in text:
    raise SystemExit("Could not locate Wazuh agent host port mapping 1514:1514")

p.write_text(text)
PY

  grep -Eq "(^|[^0-9])${WAZUH_AGENT_PORT}:1514([^0-9]|$)" "$compose" || \
    die "Wazuh agent host-port remap ${WAZUH_AGENT_PORT}:1514 is missing after patch."
  if grep -Eq '(^|[^0-9])1514:1514([^0-9]|$)' "$compose"; then
    die "Wazuh still publishes host TCP/1514; this would conflict with Shuffle/Tenzir."
  fi

  ok "Wazuh dashboard mapped to https://localhost:${WAZUH_DASHBOARD_PORT}"
  ok "Wazuh agent mapped to host TCP/${WAZUH_AGENT_PORT} -> container TCP/1514; host TCP/1514 reserved for Shuffle/Tenzir"
}

detect_wazuh_image_accounts() {
  phase "DETECT WAZUH BETA5 CONTAINER USERS"
  detect_one() {
    local image="$1" account="$2" out uid gid
    out="$(docker run --rm --entrypoint sh "$image" -lc "u=\$(id -u '$account' 2>/dev/null || id -u); g=\$(id -g '$account' 2>/dev/null || id -g); printf '%s:%s\n' \"\$u\" \"\$g\"")" || die "Could not determine UID/GID for $account in $image"
    uid="${out%%:*}"; gid="${out##*:}"
    [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || die "Unexpected UID/GID result for $account in $image: $out"
    printf '%s:%s' "$uid" "$gid"
  }

  local pair
  pair="$(detect_one "wazuh/wazuh-indexer:${WAZUH_VERSION}" "wazuh-indexer")"
  WAZUH_INDEXER_UID="${pair%%:*}"; WAZUH_INDEXER_GID="${pair##*:}"
  pair="$(detect_one "wazuh/wazuh-manager:${WAZUH_VERSION}" "wazuh-manager")"
  WAZUH_MANAGER_UID="${pair%%:*}"; WAZUH_MANAGER_GID="${pair##*:}"
  pair="$(detect_one "wazuh/wazuh-dashboard:${WAZUH_VERSION}" "wazuh-dashboard")"
  WAZUH_DASHBOARD_UID="${pair%%:*}"; WAZUH_DASHBOARD_GID="${pair##*:}"

  log "beta5 indexer user:   ${WAZUH_INDEXER_UID}:${WAZUH_INDEXER_GID}"
  log "beta5 manager user:   ${WAZUH_MANAGER_UID}:${WAZUH_MANAGER_GID}"
  log "beta5 dashboard user: ${WAZUH_DASHBOARD_UID}:${WAZUH_DASHBOARD_GID}"
  ok "Detected service UID/GID values from the actual beta5 images"
}

verify_wazuh_cert_mounts() {
  phase "VERIFY CERTIFICATE MOUNTS BEFORE STARTUP"
  check_service_mounts() {
    local service="$1" uid="$2" gid="$3"; shift 3
    local test_cmd="id; " p
    for p in "$@"; do
      test_cmd+="echo CHECK:$p; ls -ln '$p'; test -r '$p' || exit 42; "
    done
    log "Testing certificate readability for $service as UID:GID ${uid}:${gid}"
    if ! (cd "$WAZUH_SINGLE" && docker compose run --rm --no-deps --user "${uid}:${gid}" --entrypoint sh "$service" -lc "$test_cmd"); then
      find "$WAZUH_SINGLE/config" -maxdepth 4 -type f -name '*.pem' -printf '%m %u:%g %p\n' | sort || true
      die "Certificate mount/readability preflight failed for $service"
    fi
  }

  check_service_mounts "wazuh.indexer" "$WAZUH_INDEXER_UID" "$WAZUH_INDEXER_GID" \
    "/usr/share/wazuh-indexer/config/certs/root-ca.pem" \
    "/usr/share/wazuh-indexer/config/certs/indexer.pem" \
    "/usr/share/wazuh-indexer/config/certs/indexer-key.pem" \
    "/usr/share/wazuh-indexer/config/certs/admin.pem" \
    "/usr/share/wazuh-indexer/config/certs/admin-key.pem"
  check_service_mounts "wazuh.manager" "$WAZUH_MANAGER_UID" "$WAZUH_MANAGER_GID" \
    "/var/wazuh-manager/etc/certs/root-ca.pem" \
    "/var/wazuh-manager/etc/certs/indexer-connector.pem" \
    "/var/wazuh-manager/etc/certs/indexer-connector-key.pem"
  check_service_mounts "wazuh.dashboard" "$WAZUH_DASHBOARD_UID" "$WAZUH_DASHBOARD_GID" \
    "/usr/share/wazuh-dashboard/config/certs/root-ca.pem" \
    "/usr/share/wazuh-dashboard/config/certs/dashboard.pem" \
    "/usr/share/wazuh-dashboard/config/certs/dashboard-key.pem"
  ok "All Wazuh certificate bind mounts are readable by their real beta5 service users"
}

compose_service_id() {
  local service="$1"
  (cd "$WAZUH_SINGLE" && docker compose ps -q --all "$service" 2>/dev/null | head -1)
}

compose_service_name() {
  local service="$1" id
  id="$(compose_service_id "$service")"
  [[ -n "$id" ]] || return 1
  docker inspect -f '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##'
}

compose_service_running() {
  local service="$1" id
  id="$(compose_service_id "$service")"
  [[ -n "$id" ]] || return 1
  [[ "$(docker inspect -f '{{.State.Running}}' "$id" 2>/dev/null || echo false)" == "true" ]]
}

compose_service_health() {
  local service="$1" id
  id="$(compose_service_id "$service")"
  [[ -n "$id" ]] || { echo missing; return; }
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id" 2>/dev/null || echo missing
}

wait_wazuh_service() {
  local service="$1" timeout="$2" start now health name
  start="$(date +%s)"
  while true; do
    health="$(compose_service_health "$service")"
    if compose_service_running "$service" && [[ "$health" == "healthy" || "$health" == "none" ]]; then
      name="$(compose_service_name "$service" || echo "$service")"
      ok "$service ready: container=$name health=$health"
      return 0
    fi
    now="$(date +%s)"
    if (( now-start>=timeout )); then
      warn "$service readiness timeout; last health=$health"
      return 1
    fi
    sleep 8
  done
}

dump_wazuh_diagnostics() {
  echo
  log "===== WAZUH COMPOSE STATUS ====="
  (cd "$WAZUH_SINGLE" && docker compose ps -a) || true
  local service id
  for service in wazuh.indexer wazuh.manager wazuh.dashboard; do
    id="$(compose_service_id "$service" || true)"
    if [[ -n "$id" ]]; then
      echo
      log "===== $service / $(compose_service_name "$service" || echo "$id") ====="
      docker inspect "$id" --format 'running={{.State.Running}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} exit={{.State.ExitCode}}' 2>/dev/null || true
      docker logs --tail 300 "$id" 2>&1 || true
    else
      warn "No container found for Compose service $service"
    fi
  done
}
