#!/usr/bin/env bash
# shellcheck shell=bash

# Wazuh Dashboard's effective API endpoint is initialized from the Docker
# environment and persisted in the Wazuh plugin configuration. Keep both
# sources aligned so the image entrypoint cannot regenerate TCP/55000.
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

  local dashboard_cfg_dir="$WAZUH_SINGLE/config/wazuh_dashboard"
  local dashboard_cfg="$dashboard_cfg_dir/wazuh.yml"
  mkdir -p "$dashboard_cfg_dir"

  log "Writing Wazuh dashboard plugin API configuration for TCP/${WAZUH_API_PORT}"
  cat >"$dashboard_cfg" <<EOF
hosts:
  - default:
      url: https://wazuh.manager
      port: ${WAZUH_API_PORT}
      username: wazuh-wui
      password: wazuh-wui
      run_as: true
EOF

  chmod 0640 "$dashboard_cfg"
  chown "${WAZUH_DASHBOARD_UID}:${WAZUH_DASHBOARD_GID}" "$dashboard_cfg"

  grep -Eq "^[[:space:]]*port:[[:space:]]*${WAZUH_API_PORT}[[:space:]]*$" "$dashboard_cfg" || \
    die "Dashboard wazuh.yml does not contain API TCP/${WAZUH_API_PORT}."

  # Patch the dashboard service's initializer source as well. Wazuh's Docker
  # image uses WAZUH_API_URL during startup to build the effective API host.
  # Including the port here prevents the entrypoint from falling back to the
  # upstream default TCP/55000.
  python3 - "$WAZUH_SINGLE/docker-compose.yml" "$WAZUH_API_PORT" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
port = sys.argv[2]
text = p.read_text()

m = re.search(r'(?ms)^  wazuh\.dashboard:\n(?P<body>.*?)(?=^  [A-Za-z0-9_.-]+:|^volumes:)', text)
if not m:
    raise SystemExit("Could not locate wazuh.dashboard service block")
body = m.group('body')

new_body, count = re.subn(
    r'(?m)^(\s*-\s*WAZUH_API_URL=)https://wazuh\.manager(?::\d+)?\s*$',
    rf'\1https://wazuh.manager:{port}',
    body,
    count=1,
)
if count != 1:
    raise SystemExit("Could not locate WAZUH_API_URL in wazuh.dashboard environment")

mount = "      - ./config/wazuh_dashboard/wazuh.yml:/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml:ro\n"
if "/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml" not in new_body:
    vm = re.search(r'(?ms)(^    volumes:\n)(.*?)(?=^    depends_on:|^    [A-Za-z0-9_.-]+:|\Z)', new_body)
    if not vm:
        raise SystemExit("Could not locate wazuh.dashboard volumes block")
    insert_at = vm.start(2) + len(vm.group(2))
    new_body = new_body[:insert_at] + mount + new_body[insert_at:]

text = text[:m.start('body')] + new_body + text[m.end('body'):]
p.write_text(text)
PY

  grep -Fq "WAZUH_API_URL=https://wazuh.manager:${WAZUH_API_PORT}" "$WAZUH_SINGLE/docker-compose.yml" || \
    die "Wazuh dashboard initializer API URL is not set to wazuh.manager:${WAZUH_API_PORT}."
  grep -Fq '/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml:ro' "$WAZUH_SINGLE/docker-compose.yml" || \
    die "Wazuh dashboard wazuh.yml bind mount is missing after patch."

  (cd "$WAZUH_SINGLE" && docker compose config --quiet) || \
    die "Wazuh Compose became invalid after dashboard API configuration patch."

  ok "Wazuh manager API and dashboard initializer/plugin configured for TCP/${WAZUH_API_PORT}"
}

verify_wazuh_api_runtime_configuration() {
  local manager_id dashboard_id manager_code dashboard_code dashboard_env
  manager_id="$(compose_service_id wazuh.manager)"
  dashboard_id="$(compose_service_id wazuh.dashboard)"
  [[ -n "$manager_id" && -n "$dashboard_id" ]] || die "Cannot verify Wazuh API runtime configuration; manager/dashboard container missing."

  docker exec "$manager_id" sh -lc \
    "grep -Eq '^[[:space:]]*port:[[:space:]]*${WAZUH_API_PORT}[[:space:]]*$' /var/wazuh-manager/api/configuration/api.yaml" || \
    die "Running Wazuh manager API configuration is not set to TCP/${WAZUH_API_PORT}."

  dashboard_env="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$dashboard_id" | grep '^WAZUH_API_URL=' || true)"
  [[ "$dashboard_env" == "WAZUH_API_URL=https://wazuh.manager:${WAZUH_API_PORT}" ]] || \
    die "Running Wazuh dashboard initializer still has '${dashboard_env:-no WAZUH_API_URL}'."

  docker exec "$dashboard_id" sh -lc \
    "grep -Eq '^[[:space:]]*port:[[:space:]]*${WAZUH_API_PORT}[[:space:]]*$' /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml && grep -Fq 'url: https://wazuh.manager' /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml" || \
    die "Running Wazuh dashboard plugin configuration does not reference wazuh.manager API TCP/${WAZUH_API_PORT}."

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

  ok "Wazuh API is configured and reachable on TCP/${WAZUH_API_PORT}; dashboard initializer and plugin config agree"
}
