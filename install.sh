#!/usr/bin/env bash
# SOC Lab installer / operations entrypoint
# Wazuh 5.0.0-beta5 + Shuffle on WSL2 / Docker Desktop
set -Eeuo pipefail
umask 077

WAZUH_VERSION="5.0.0-beta5"
WAZUH_REF="v${WAZUH_VERSION}"
ROOT_DIR="${SOCLAB_ROOT:-/opt/soclab}"
WAZUH_DIR="$ROOT_DIR/wazuh-docker"
WAZUH_SINGLE="$WAZUH_DIR/single-node"
SHUFFLE_DIR="$ROOT_DIR/Shuffle"
STATE_DIR="$ROOT_DIR/state"
WAZUH_DASHBOARD_PORT="${WAZUH_DASHBOARD_PORT:-8443}"
SHUFFLE_FRONTEND_PORT="${SHUFFLE_FRONTEND_PORT:-3001}"
SHUFFLE_HTTPS_PORT="${SHUFFLE_HTTPS_PORT:-3443}"
SHUFFLE_BACKEND_PORT="${SHUFFLE_BACKEND_PORT:-5001}"
SHUFFLE_OPENSEARCH_PORT="${SHUFFLE_OPENSEARCH_PORT:-9201}"
LOG="/tmp/soclab-full-clean-beta5-$(date +%Y%m%d-%H%M%S).log"

WAZUH_INDEXER_UID=""
WAZUH_INDEXER_GID=""
WAZUH_MANAGER_UID=""
WAZUH_MANAGER_GID=""
WAZUH_DASHBOARD_UID=""
WAZUH_DASHBOARD_GID=""
WAZUH_ADMIN_USER="admin"
WAZUH_ADMIN_PASSWORD=""
WAZUH_DASHBOARD_SERVICE_USER="kibanaserver"
WAZUH_DASHBOARD_SERVICE_PASSWORD=""
WAZUH_API_USER="wazuh-wui"
WAZUH_API_PASSWORD=""
SHUFFLE_ADMIN_USERNAME="admin@soclab.local"
SHUFFLE_ADMIN_PASSWORD=""
SHUFFLE_OPENSEARCH_PASSWORD=""
SHUFFLE_API_KEY=""
SHUFFLE_ENCRYPTION_MODIFIER=""

exec > >(tee -a "$LOG") 2>&1
log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
ok()   { log "[OK] $*"; }
warn() { log "[WARN] $*"; }
die()  { log "[FAIL] $*"; exit 1; }
on_error() { local rc=$?; warn "Installer failed at line ${BASH_LINENO[0]:-unknown}; exit=${rc}"; warn "Complete log: $LOG"; exit "$rc"; }
trap on_error ERR
need_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run with sudo: sudo bash $0"; }
have() { command -v "$1" >/dev/null 2>&1; }
phase() { echo; log "============================================================"; log "$*"; log "============================================================"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/credentials.sh
source "$SCRIPT_DIR/lib/credentials.sh"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/wazuh.sh
source "$SCRIPT_DIR/lib/wazuh.sh"
# shellcheck source=lib/shuffle.sh
source "$SCRIPT_DIR/lib/shuffle.sh"
# shellcheck source=lib/healthcheck.sh
source "$SCRIPT_DIR/lib/healthcheck.sh"

install_all() {
  need_root
  check_docker

  phase "SOC LAB CLEAN INSTALL - WAZUH ${WAZUH_VERSION} + SHUFFLE"
  log "This will erase ONLY the previous /opt/soclab, /opt/soar-lab, and their lab-owned Docker Compose state."

  collect_runtime_credentials
  clean_lab
  write_credentials_file

  phase "HOST PREPARATION"
  install_prereqs
  check_resources
  configure_host

  phase "PHASE 2/7 - CLONE AND PREPARE WAZUH ${WAZUH_VERSION}"

  git clone \
    --depth 1 \
    --branch "$WAZUH_REF" \
    https://github.com/wazuh/wazuh-docker.git \
    "$WAZUH_DIR"

  [[ -f "$WAZUH_SINGLE/docker-compose.yml" ]] || \
    die "Missing beta5 single-node Compose file."

  for component in manager indexer dashboard; do
    grep -q "wazuh/wazuh-${component}:${WAZUH_VERSION}" "$WAZUH_SINGLE/docker-compose.yml" || \
      die "Compose file does not reference wazuh-${component}:${WAZUH_VERSION}"
  done

  patch_wazuh_dashboard_port

  log "Validating Wazuh Compose configuration"
  (cd "$WAZUH_SINGLE" && docker compose config --quiet)

  log "Pulling/verifying Wazuh ${WAZUH_VERSION} images"
  (cd "$WAZUH_SINGLE" && docker compose pull)

  detect_wazuh_image_accounts
  generate_wazuh_certs_locally
  configure_wazuh_runtime_credentials
  verify_wazuh_cert_mounts

  phase "PHASE 4/7 - START AND VERIFY WAZUH ${WAZUH_VERSION}"

  log "Starting Wazuh"
  if ! (cd "$WAZUH_SINGLE" && docker compose up -d --remove-orphans); then
    dump_wazuh_diagnostics
    die "docker compose up failed for Wazuh."
  fi

  wait_wazuh_service "wazuh.indexer" 480 || { dump_wazuh_diagnostics; die "Wazuh indexer did not become healthy."; }
  wait_wazuh_service "wazuh.manager" 420 || { dump_wazuh_diagnostics; die "Wazuh manager did not become healthy."; }
  wait_wazuh_service "wazuh.dashboard" 420 || { dump_wazuh_diagnostics; die "Wazuh dashboard did not become healthy."; }

  local indexer_id
  indexer_id="$(compose_service_id wazuh.indexer)"
  if docker exec "$indexer_id" sh -lc \
      'curl -fks https://localhost:9200/_plugins/_security/health | grep -q "\"status\":\"UP\""' \
      >/dev/null 2>&1; then
    ok "Indexer Security health endpoint reports UP"
  else
    dump_wazuh_diagnostics
    die "Indexer Security health endpoint is not UP."
  fi

  local start code
  start="$(date +%s)"
  while true; do
    code="$(curl -ksS -o /tmp/soclab-dashboard-http.out -w '%{http_code}' --max-time 10 \
      "https://localhost:${WAZUH_DASHBOARD_PORT}/login" || true)"
    case "$code" in
      200|301|302|401|403) ok "Dashboard HTTPS endpoint reachable (HTTP $code)"; break ;;
    esac
    if (( $(date +%s) - start >= 180 )); then
      dump_wazuh_diagnostics
      die "Wazuh dashboard /login did not return a valid HTTP response (last HTTP ${code:-none})."
    fi
    sleep 8
  done

  code="$(curl -ksS -o /tmp/soclab-indexer-http.out -w '%{http_code}' --max-time 10 https://localhost:9200/ || true)"
  case "$code" in
    200|401|403) ok "Indexer HTTPS endpoint reachable (HTTP $code)" ;;
    *) dump_wazuh_diagnostics; die "Indexer HTTPS endpoint failed (HTTP ${code:-none})." ;;
  esac

  code="$(curl -ksS -o /tmp/soclab-wazuh-api-http.out -w '%{http_code}' --max-time 10 https://localhost:55000/ || true)"
  case "$code" in
    200|401|403|404) ok "Wazuh API HTTPS listener reachable (HTTP $code)" ;;
    *) dump_wazuh_diagnostics; die "Wazuh API listener failed (HTTP ${code:-none})." ;;
  esac

  verify_runtime_credentials
  ok "WAZUH ${WAZUH_VERSION} PASSED ALL HEALTH GATES"

  install_shuffle
  final_health
  print_report
}

usage() {
  cat <<EOF
Usage: sudo ./install.sh <command>

Commands:
  install       Full clean install of Wazuh ${WAZUH_VERSION} + Shuffle
  healthcheck   Run reusable end-to-end healthcheck
  status        Show Docker Compose status and lab URLs
  logs [target] Show last 300 log lines; target: wazuh|shuffle|all
  reset         Remove only SOC-lab-owned state
  credentials   Show local mode-600 credential inventory path; does not print secrets
  help          Show this help

Environment overrides:
  SOCLAB_ROOT                 default: /opt/soclab
  WAZUH_DASHBOARD_PORT        default: 8443
  SHUFFLE_FRONTEND_PORT       default: 3001
  SHUFFLE_HTTPS_PORT          default: 3443
  SHUFFLE_BACKEND_PORT        default: 5001
  SHUFFLE_OPENSEARCH_PORT     default: 9201
EOF
}

dispatch() {
  local cmd="${1:-install}"
  shift || true
  case "$cmd" in
    install) install_all "$@" ;;
    healthcheck|health) healthcheck_all "$@" ;;
    status) status_all "$@" ;;
    logs) logs_cmd "$@" ;;
    reset|clean) reset_cmd "$@" ;;
    credentials) credentials_cmd "$@" ;;
    help|-h|--help) usage ;;
    *) usage; die "Unknown command: $cmd" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  dispatch "$@"
fi
