#!/usr/bin/env bash
# shellcheck shell=bash

# Shuffle's built-in Tenzir/Sigma runtime publishes host TCP/1514. Keep Wazuh
# listening on its normal container port 1514, but publish it on a distinct
# host port so both products can coexist on the same Docker Desktop daemon.
WAZUH_AGENT_PORT="${WAZUH_AGENT_PORT:-15140}"

# Wazuh's REST API defaults to TCP/55000 upstream, but the API port is a
# supported configuration option. Windows/HNS can reserve 55000, so this lab
# configures the actual Wazuh API listener (not only Docker NAT) on TCP/15500.
WAZUH_API_PORT="${WAZUH_API_PORT:-15500}"

patch_wazuh_dashboard_port() {
  local compose="$WAZUH_SINGLE/docker-compose.yml"
  python3 - "$compose" "$WAZUH_DASHBOARD_PORT" "$WAZUH_AGENT_PORT" "$WAZUH_API_PORT" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
dashboard_port = sys.argv[2]
agent_port = sys.argv[3]
api_port = sys.argv[4]
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

# The manager itself will be configured to listen on api_port. Publish that
# same port on loopback; this is intentionally not host-port translation.
before_api = text
api_patterns = [
    r'(?m)^(\s*-\s*)"?55000:55000"?\s*$',
    r'(?m)^(\s*-\s*)"?0\.0\.0\.0:55000:55000"?\s*$',
    r'(?m)^(\s*-\s*)"?127\.0\.0\.1:55000:55000"?\s*$',
]
for pattern in api_patterns:
    text = re.sub(pattern, rf'\1"127.0.0.1:{api_port}:{api_port}"', text)
if text == before_api and f"127.0.0.1:{api_port}:{api_port}" not in text:
    raise SystemExit("Could not locate Wazuh API host port mapping 55000:55000")

p.write_text(text)
PY

  grep -Eq "(^|[^0-9])${WAZUH_AGENT_PORT}:1514([^0-9]|$)" "$compose" || \
    die "Wazuh agent host-port remap ${WAZUH_AGENT_PORT}:1514 is missing after patch."
  if grep -Eq '(^|[^0-9])1514:1514([^0-9]|$)' "$compose"; then
    die "Wazuh still publishes host TCP/1514; this would conflict with Shuffle/Tenzir."
  fi

  grep -Fq "127.0.0.1:${WAZUH_API_PORT}:${WAZUH_API_PORT}" "$compose" || \
    die "Wazuh API Compose mapping must be host/container TCP/${WAZUH_API_PORT} on loopback."
  if grep -Eq '(^|[^0-9])55000:55000([^0-9]|$)' "$compose"; then
    die "Wazuh Compose still publishes the upstream default TCP/55000."
  fi

  grep -Eq '(^|[^0-9])1515:1515([^0-9]|$)' "$compose" || die "Wazuh enrollment TCP/1515 mapping is missing."
  grep -Eq '(^|[^0-9])514:514/udp([^0-9]|$)' "$compose" || die "Wazuh syslog UDP/514 mapping is missing."

  ok "Wazuh dashboard mapped to https://localhost:${WAZUH_DASHBOARD_PORT}"
  ok "Wazuh agent mapped to host TCP/${WAZUH_AGENT_PORT} -> container TCP/1514; host TCP/1514 reserved for Shuffle/Tenzir"
  ok "Wazuh API Docker mapping set to 127.0.0.1:${WAZUH_API_PORT} -> container TCP/${WAZUH_API_PORT}"
}

configure_wazuh_api_runtime() {
  [[ "$WAZUH_API_PORT" =~ ^[0-9]+$ ]] || die "WAZUH_API_PORT must be numeric."
  (( WAZUH_API_PORT >= 1 && WAZUH_API_PORT <= 65535 )) || die "WAZUH_API_PORT must be between 1 and 65535."

  phase "CONFIGURE WAZUH API TCP/${WAZUH_API_PORT}"

  log "Configuring manager API listener in the persistent Wazuh API configuration volume"
  if ! (cd "$WAZUH_SINGLE" && docker compose run --rm --no-deps \
      -e "SOCLAB_WAZUH_API_PORT=${WAZUH_API_PORT}" \
      --entrypoint sh wazuh.manager -lc '
        set -eu
        cfg=/var/wazuh-manager/api/configuration/api.yaml
        test -f "$cfg" || { echo "Missing $cfg" >&2; exit 41; }
        port="$SOCLAB_WAZUH_API_PORT"
        if grep -Eq "^[[:space:]]*#?[[:space:]]*port:[[:space:]]*[0-9]+[[:space:]]*$" "$cfg"; then
          sed -Ei "0,/^[[:space:]]*#?[[:space:]]*port:[[:space:]]*[0-9]+[[:space:]]*$/s//port: ${port}/" "$cfg"
        else
          printf "\nport: %s\n" "$port" >>"$cfg"
        fi
        grep -Eq "^[[:space:]]*port:[[:space:]]*${port}[[:space:]]*$" "$cfg"
      '); then
    die "Could not configure Wazuh manager API listener on TCP/${WAZUH_API_PORT}."
  fi

  log "Configuring Wazuh dashboard manager connection to TCP/${WAZUH_API_PORT}"
  if ! (cd "$WAZUH_SINGLE" && docker compose run --rm --no-deps \
      -e "SOCLAB_WAZUH_API_PORT=${WAZUH_API_PORT}" \
      --entrypoint sh wazuh.dashboard -lc '
        set -eu
        cfg=/usr/share/wazuh-dashboard/config/opensearch_dashboards.yml
        test -f "$cfg" || { echo "Missing $cfg" >&2; exit 42; }
        port="$SOCLAB_WAZUH_API_PORT"
        grep -Eq "^[[:space:]]*wazuh_core\.hosts:[[:space:]]*$" "$cfg" || {
          echo "wazuh_core.hosts block missing from $cfg" >&2
          exit 43
        }
        grep -Eq "^[[:space:]]*port:[[:space:]]*[0-9]+[[:space:]]*$" "$cfg" || {
          echo "Wazuh API port field missing from dashboard configuration" >&2
          exit 44
        }
        sed -Ei "0,/^([[:space:]]*)port:[[:space:]]*[0-9]+[[:space:]]*$/s//\1port: ${port}/" "$cfg"
        grep -Eq "^[[:space:]]*port:[[:space:]]*${port}[[:space:]]*$" "$cfg"
      '); then
    die "Could not configure Wazuh dashboard to use manager API TCP/${WAZUH_API_PORT}."
  fi

  ok "Wazuh manager and dashboard runtime configuration prepared for API TCP/${WAZUH_API_PORT}"
}

verify_wazuh_api_runtime_configuration() {
  local manager_id dashboard_id manager_code dashboard_code
  manager_id="$(compose_service_id wazuh.manager)"
  dashboard_id="$(compose_service_id wazuh.dashboard)"
  [[ -n "$manager_id" && -n "$dashboard_id" ]] || die "Cannot verify Wazuh API runtime configuration; manager/dashboard container missing."

  docker exec "$manager_id" sh -lc \
    "grep -Eq '^[[:space:]]*port:[[:space:]]*${WAZUH_API_PORT}[[:space:]]*$' /var/wazuh-manager/api/configuration/api.yaml" || \
    die "Running Wazuh manager API configuration is not set to TCP/${WAZUH_API_PORT}."

  docker exec "$dashboard_id" sh -lc \
    "grep -Eq '^[[:space:]]*wazuh_core\\.hosts:[[:space:]]*$' /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml && grep -Eq '^[[:space:]]*port:[[:space:]]*${WAZUH_API_PORT}[[:space:]]*$' /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml" || \
    die "Running Wazuh dashboard configuration does not reference manager API TCP/${WAZUH_API_PORT}."

  manager_code="$(docker exec "$manager_id" sh -lc \
    "curl -ksS -o /dev/null -w '%{http_code}' --max-time 10 https://localhost:${WAZUH_API_PORT}/ || true" 2>/dev/null || true)"
  case "$manager_code" in
    200|401|403|404) ;;
    *) die "Wazuh manager is not serving its API on internal TCP/${WAZUH_API_PORT} (HTTP ${manager_code:-none})." ;;
  esac

  dashboard_code="$(docker exec "$dashboard_id" sh -lc \
    "curl -ksS -o /dev/null -w '%{http_code}' --max-time 10 https://wazuh.manager:${WAZUH_API_PORT}/ || true" 2>/dev/null || true)"
  case "$dashboard_code" in
    200|401|403|404) ;;
    *) die "Wazuh dashboard cannot reach manager API on TCP/${WAZUH_API_PORT} (HTTP ${dashboard_code:-none})." ;;
  esac

  ok "Wazuh API is configured and reachable on TCP/${WAZUH_API_PORT} from manager, dashboard, and Docker network"
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
