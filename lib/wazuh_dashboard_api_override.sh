#!/usr/bin/env bash
# shellcheck shell=bash

# Wazuh Dashboard has two distinct API endpoint inputs:
#   * WAZUH_API_URL is the manager base URL (scheme + host only)
#   * wazuh.yml carries the API TCP port
# Keep those semantics separate. Supplying a port in WAZUH_API_URL makes the
# dashboard initializer append its own port and can create an invalid URL such
# as https://wazuh.manager:15500:55000.
configure_wazuh_api_runtime() {
  [[ "$WAZUH_API_PORT" =~ ^[0-9]+$ ]] || die "WAZUH_API_PORT must be numeric."
  (( WAZUH_API_PORT >= 1 && WAZUH_API_PORT <= 65535 )) || die "WAZUH_API_PORT must be between 1 and 65535."

  phase "CONFIGURE WAZUH API TCP/${WAZUH_API_PORT}"

  # Wazuh 5.0.0-beta5 moved the manager runtime root from /var/ossec to
  # /var/wazuh-manager. We verified this image contains and honors this file.
  log "Configuring manager API listener in /var/wazuh-manager/api/configuration/api.yaml"
  if ! (cd "$WAZUH_SINGLE" && docker compose run --rm --no-deps \
      -e "SOCLAB_WAZUH_API_PORT=${WAZUH_API_PORT}" \
      --entrypoint sh wazuh.manager -lc '
        set -eu
        cfg=/var/wazuh-manager/api/configuration/api.yaml
        test -f "$cfg" || { echo "Missing $cfg" >&2; exit 41; }
        port="$SOCLAB_WAZUH_API_PORT"

        # beta5 ships api.yaml mostly commented. Preserve vendor comments and
        # remove only already-active top-level host/port entries. Then append
        # one authoritative SOCLab pair. JSON-style lists are valid YAML and
        # avoid fragile nested single-quote handling inside sh -lc.
        tmp="${cfg}.soclab.$$"
        grep -Ev "^[[:space:]]*(host|port):" "$cfg" >"$tmp" || true
        printf "\\nhost: [\\\"0.0.0.0\\\", \\\"::\\\"]\\nport: %s\\n" "$port" >>"$tmp"
        cat "$tmp" >"$cfg"
        rm -f "$tmp"

        grep -Eq "^[[:space:]]*port:[[:space:]]*${port}[[:space:]]*$" "$cfg"
        grep -Fq "host: [\\\"0.0.0.0\\\", \\\"::\\\"]" "$cfg"
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
  grep -Fq 'url: https://wazuh.manager' "$dashboard_cfg" || \
    die "Dashboard wazuh.yml does not target wazuh.manager."

  # Wazuh Docker expects WAZUH_API_URL to contain only scheme + manager host.
  # The custom port belongs exclusively in wazuh.yml.
  python3 - "$WAZUH_SINGLE/docker-compose.yml" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()

m = re.search(r'(?ms)^  wazuh\.dashboard:\n(?P<body>.*?)(?=^  [A-Za-z0-9_.-]+:|^volumes:)', text)
if not m:
    raise SystemExit("Could not locate wazuh.dashboard service block")
body = m.group('body')

new_body, count = re.subn(
    r'(?m)^(\s*-\s*WAZUH_API_URL=)https://wazuh\.manager(?::\d+)?\s*$',
    r'\1https://wazuh.manager',
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

  grep -Fq 'WAZUH_API_URL=https://wazuh.manager' "$WAZUH_SINGLE/docker-compose.yml" || \
    die "Wazuh dashboard initializer API URL is not host-only https://wazuh.manager."
  if grep -Eq 'WAZUH_API_URL=https://wazuh\.manager:[0-9]+' "$WAZUH_SINGLE/docker-compose.yml"; then
    die "Wazuh dashboard initializer API URL incorrectly contains a port; the port belongs in wazuh.yml."
  fi
  grep -Fq '/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml:ro' "$WAZUH_SINGLE/docker-compose.yml" || \
    die "Wazuh dashboard wazuh.yml bind mount is missing after patch."

  (cd "$WAZUH_SINGLE" && docker compose config --quiet) || \
    die "Wazuh Compose became invalid after dashboard API configuration patch."

  ok "Wazuh beta5 manager API configured in /var/wazuh-manager/api/configuration/api.yaml on TCP/${WAZUH_API_PORT}; dashboard URL is host-only and plugin port is ${WAZUH_API_PORT}"
}

verify_wazuh_api_runtime_configuration() {
  local manager_id dashboard_id manager_code dashboard_code dashboard_env mounted_cfg
  manager_id="$(compose_service_id wazuh.manager)"
  dashboard_id="$(compose_service_id wazuh.dashboard)"
  [[ -n "$manager_id" && -n "$dashboard_id" ]] || die "Cannot verify Wazuh API runtime configuration; manager/dashboard container missing."

  docker exec "$manager_id" sh -lc \
    "grep -Eq '^[[:space:]]*port:[[:space:]]*${WAZUH_API_PORT}[[:space:]]*$' /var/wazuh-manager/api/configuration/api.yaml && grep -Fq 'host: [\"0.0.0.0\", \"::\"]' /var/wazuh-manager/api/configuration/api.yaml" || \
    die "Running Wazuh beta5 manager API configuration is not set to host [0.0.0.0, ::] and TCP/${WAZUH_API_PORT}."

  dashboard_env="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$dashboard_id" | grep '^WAZUH_API_URL=' || true)"
  [[ "$dashboard_env" == "WAZUH_API_URL=https://wazuh.manager" ]] || \
    die "Running Wazuh dashboard WAZUH_API_URL must be host-only; found '${dashboard_env:-no WAZUH_API_URL}'."

  mounted_cfg="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml"}}{{println .Source "->" .Destination .Mode}}{{end}}{{end}}' "$dashboard_id" || true)"
  [[ -n "$mounted_cfg" ]] || \
    die "Running Wazuh dashboard does not have the SOCLab wazuh.yml bind mount."

  docker exec "$dashboard_id" sh -lc \
    "grep -Eq '^[[:space:]]*port:[[:space:]]*${WAZUH_API_PORT}[[:space:]]*$' /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml && grep -Fq 'url: https://wazuh.manager' /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml && ! grep -Eq '^[[:space:]]*port:[[:space:]]*55000[[:space:]]*$' /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml" || \
    die "Running Wazuh dashboard plugin configuration does not exclusively reference wazuh.manager API TCP/${WAZUH_API_PORT}."

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

  if docker logs --tail 300 "$dashboard_id" 2>&1 | grep -Eq 'wazuh\.manager:[0-9]+:55000|wazuh\.manager:55000'; then
    die "Wazuh dashboard logs still show an invalid/default TCP/55000 manager API endpoint."
  fi

  ok "Wazuh API endpoint contract verified: beta5 /var/wazuh-manager listener TCP/${WAZUH_API_PORT} + host-only dashboard URL + plugin TCP/${WAZUH_API_PORT}"
}
