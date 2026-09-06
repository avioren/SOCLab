#!/usr/bin/env bash
# shellcheck shell=bash

# Wazuh Dashboard's Wazuh-plugin API endpoint is stored in wazuh.yml, not in
# opensearch_dashboards.yml. Keep these overrides separate so the beta5 runtime
# path is explicit and testable.
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

  local dashboard_cfg="$WAZUH_SINGLE/config/wazuh_dashboard/wazuh.yml"
  [[ -f "$dashboard_cfg" ]] || die "Pinned Wazuh dashboard plugin configuration is missing: $dashboard_cfg"

  log "Configuring Wazuh dashboard plugin manager connection in wazuh.yml to TCP/${WAZUH_API_PORT}"
  python3 - "$dashboard_cfg" "$WAZUH_API_PORT" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
port = sys.argv[2]
text = p.read_text()

# Wazuh's dashboard plugin config has a hosts/default block with a numeric port.
# Replace the first API port field in that file; the pinned file is dedicated
# to the Wazuh manager API endpoint.
new, count = re.subn(
    r'(?m)^(\s*port:\s*)\d+(\s*)$',
    rf'\g<1>{port}\2',
    text,
    count=1,
)
if count != 1:
    raise SystemExit("Could not locate dashboard Wazuh API port in wazuh.yml")
p.write_text(new)
PY

  grep -Eq "^[[:space:]]*port:[[:space:]]*${WAZUH_API_PORT}[[:space:]]*$" "$dashboard_cfg" || \
    die "Dashboard wazuh.yml does not contain API TCP/${WAZUH_API_PORT} after patch."

  # Ensure beta5 uses this exact file even if its image entrypoint would
  # otherwise generate plugin configuration from default environment values.
  python3 - "$WAZUH_SINGLE/docker-compose.yml" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
mount = "      - ./config/wazuh_dashboard/wazuh.yml:/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml:ro\n"
if "/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml" not in text:
    m = re.search(r'(?ms)(^  wazuh\.dashboard:\n.*?^    volumes:\n)(.*?)(?=^    depends_on:|^  [A-Za-z0-9_.-]+:|^volumes:)', text)
    if not m:
        raise SystemExit("Could not locate wazuh.dashboard volumes block")
    block = m.group(1) + m.group(2)
    insert_at = m.start(1) + len(block)
    text = text[:insert_at] + mount + text[insert_at:]
p.write_text(text)
PY

  grep -Fq '/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml:ro' "$WAZUH_SINGLE/docker-compose.yml" || \
    die "Wazuh dashboard wazuh.yml bind mount is missing after patch."

  (cd "$WAZUH_SINGLE" && docker compose config --quiet) || \
    die "Wazuh Compose became invalid after adding dashboard wazuh.yml mount."

  ok "Wazuh manager API and dashboard plugin configured for TCP/${WAZUH_API_PORT}"
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
    "grep -Eq '^[[:space:]]*port:[[:space:]]*${WAZUH_API_PORT}[[:space:]]*$' /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml" || \
    die "Running Wazuh dashboard plugin configuration does not reference manager API TCP/${WAZUH_API_PORT}."

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

  ok "Wazuh API is configured and reachable on TCP/${WAZUH_API_PORT}; dashboard plugin wazuh.yml matches the manager"
}
