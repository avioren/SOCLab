#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAZUH_API_HOST_PORT="${WAZUH_API_HOST_PORT:-15500}"

[[ ${EUID:-$(id -u)} -eq 0 ]] || {
  echo "[FAIL] Run as root: sudo bash scripts/recover-wazuh-api-and-resume.sh" >&2
  exit 1
}

# Source installer functions/variables without dispatching a new clean install.
# shellcheck source=../install.sh
source "$REPO_ROOT/install.sh"

compose="$WAZUH_SINGLE/docker-compose.yml"
[[ -f "$compose" ]] || {
  echo "[FAIL] Existing Wazuh Compose file not found at $compose" >&2
  echo "This recovery command is only for the interrupted Wazuh startup run." >&2
  exit 1
}

log "Recovering Wazuh API host mapping after Docker Desktop port-forward failure"
python3 - "$compose" "$WAZUH_API_HOST_PORT" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
host_port = sys.argv[2]
text = path.read_text()

patterns = [
    (r'(?m)^(\s*-\s*)"?55000:55000"?\s*$', rf'\1"{host_port}:55000"'),
    (r'(?m)^(\s*-\s*)"?0\.0\.0\.0:55000:55000"?\s*$', rf'\1"0.0.0.0:{host_port}:55000"'),
]

original = text
for pattern, replacement in patterns:
    text = re.sub(pattern, replacement, text)

if text == original and f"{host_port}:55000" not in text:
    raise SystemExit("Could not locate Wazuh API host mapping 55000:55000")

if re.search(r'(?m)(^|[^0-9])55000:55000([^0-9]|$)', text):
    raise SystemExit("Host TCP/55000 is still published after recovery patch")

path.write_text(text)
PY

log "Validating recovered Wazuh Compose configuration"
(cd "$WAZUH_SINGLE" && docker compose config --quiet)

log "Starting existing Wazuh services with host TCP/${WAZUH_API_HOST_PORT} -> container TCP/55000"
(cd "$WAZUH_SINGLE" && docker compose up -d --remove-orphans)

wait_wazuh_service "wazuh.indexer" 180 || {
  dump_wazuh_diagnostics
  die "Wazuh indexer is not healthy after recovery."
}
wait_wazuh_service "wazuh.manager" 300 || {
  dump_wazuh_diagnostics
  die "Wazuh manager is not healthy after API port recovery."
}
wait_wazuh_service "wazuh.dashboard" 300 || {
  dump_wazuh_diagnostics
  die "Wazuh dashboard is not healthy after API port recovery."
}

api_code="$(curl -ksS -o /tmp/soclab-wazuh-api-recovery.out -w '%{http_code}' --max-time 10 \
  "https://localhost:${WAZUH_API_HOST_PORT}/" || true)"
case "$api_code" in
  200|401|403|404) ok "Wazuh API reachable on https://localhost:${WAZUH_API_HOST_PORT} (HTTP $api_code)" ;;
  *) dump_wazuh_diagnostics; die "Wazuh API recovery failed (HTTP ${api_code:-none})." ;;
esac

dash_code="$(curl -ksS -o /tmp/soclab-dashboard-recovery.out -w '%{http_code}' --max-time 10 \
  "https://localhost:${WAZUH_DASHBOARD_PORT}/login" || true)"
case "$dash_code" in
  200|301|302|401|403) ok "Wazuh dashboard reachable after recovery (HTTP $dash_code)" ;;
  *) dump_wazuh_diagnostics; die "Wazuh dashboard recovery failed (HTTP ${dash_code:-none})." ;;
esac

if [[ -e "$SHUFFLE_DIR" ]]; then
  die "Shuffle path already exists at $SHUFFLE_DIR. Refusing to overwrite it in recovery mode."
fi

log "Wazuh is healthy; resuming installation at Shuffle phase"
install_shuffle
final_health

if [[ -f "$STATE_DIR/credentials.txt" ]]; then
  sed -i "s#^WAZUH_API_URL=.*#WAZUH_API_URL=https://localhost:${WAZUH_API_HOST_PORT}#" \
    "$STATE_DIR/credentials.txt"
fi

log "Running real Shuffle workflow CRUD repair/verification gate"
bash "$REPO_ROOT/scripts/repair-shuffle-workflows.sh"

cat <<EOF

============================================================
SOC LAB RECOVERY COMPLETE
============================================================
Wazuh Dashboard: https://localhost:${WAZUH_DASHBOARD_PORT}
Wazuh Indexer:   https://localhost:9200
Wazuh API:       https://localhost:${WAZUH_API_HOST_PORT}
Wazuh agent:     host TCP/${WAZUH_AGENT_PORT} -> container TCP/1514
Shuffle:         http://localhost:${SHUFFLE_FRONTEND_PORT}
Credentials:     ${STATE_DIR}/credentials.txt
============================================================
EOF

ok "Recovered Wazuh port collision, completed Shuffle install, and passed workflow CRUD gate"
