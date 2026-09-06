#!/usr/bin/env bash
# SOC Lab installer / operations entrypoint
# Wazuh 5.0.0-beta5 + Shuffle 2.2.1 on WSL2 / Docker Desktop
# Shuffle execution plane: explicit single-node Docker Swarm
set -Eeuo pipefail
umask 077

WAZUH_VERSION="5.0.0-beta5"
WAZUH_REF="v${WAZUH_VERSION}"

SHUFFLE_VERSION="${SHUFFLE_VERSION:-2.2.1}"
SHUFFLE_REF="${SHUFFLE_REF:-v${SHUFFLE_VERSION}}"
SHUFFLE_FRONTEND_IMAGE="${SHUFFLE_FRONTEND_IMAGE:-ghcr.io/shuffle/shuffle-frontend:${SHUFFLE_VERSION}}"
SHUFFLE_BACKEND_IMAGE="${SHUFFLE_BACKEND_IMAGE:-ghcr.io/shuffle/shuffle-backend:${SHUFFLE_VERSION}}"
SHUFFLE_ORBORUS_IMAGE="${SHUFFLE_ORBORUS_IMAGE:-ghcr.io/shuffle/shuffle-orborus:${SHUFFLE_VERSION}}"
SHUFFLE_WORKER_IMAGE="${SHUFFLE_WORKER_IMAGE:-ghcr.io/shuffle/shuffle-worker:${SHUFFLE_VERSION}}"
SHUFFLE_OPENSEARCH_IMAGE="${SHUFFLE_OPENSEARCH_IMAGE:-opensearchproject/opensearch:3.2.0}"
SHUFFLE_SWARM_NETWORK_NAME="${SHUFFLE_SWARM_NETWORK_NAME:-shuffle_swarm_executions}"
SHUFFLE_SWARM_MTU="${SHUFFLE_SWARM_MTU:-}"
SOCLAB_SWARM_ADVERTISE_ADDR="${SOCLAB_SWARM_ADVERTISE_ADDR:-}"

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

quiesce_shuffle_for_cleanup() {
  if docker inspect shuffle-orborus >/dev/null 2>&1; then
    log "Quiescing Shuffle Orborus before teardown"
    docker stop shuffle-orborus >/dev/null 2>&1 || true
  fi
}

remove_shuffle_swarm_services_before_compose() {
  local state exec_id core_id sid sname target cid cname svc_label deadline
  local -a remove_ids=()
  state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"
  [[ "$state" == "active" ]] || return 0
  docker node ls >/dev/null 2>&1 || return 0

  exec_id="$(docker network inspect -f '{{.Id}}' "$SHUFFLE_SWARM_NETWORK_NAME" 2>/dev/null || true)"
  core_id="$(docker network inspect -f '{{.Id}}' shuffle_shuffle 2>/dev/null || true)"

  while read -r sid; do
    [[ -n "$sid" ]] || continue
    sname="$(docker service inspect -f '{{.Spec.Name}}' "$sid" 2>/dev/null || true)"
    if [[ "$sname" == "shuffle-workers" ]]; then
      remove_ids+=("$sid")
      continue
    fi
    while read -r target; do
      [[ -n "$target" ]] || continue
      if [[ ( -n "$exec_id" && "$target" == "$exec_id" ) || ( -n "$core_id" && "$target" == "$core_id" ) ]]; then
        remove_ids+=("$sid")
        break
      fi
    done < <(docker service inspect -f '{{range .Spec.TaskTemplate.Networks}}{{println .Target}}{{end}}' "$sid" 2>/dev/null || true)
  done < <(docker service ls -q 2>/dev/null || true)

  if (( ${#remove_ids[@]} )); then
    for sid in "${remove_ids[@]}"; do
      sname="$(docker service inspect -f '{{.Spec.Name}}' "$sid" 2>/dev/null || echo "$sid")"
      log "Removing SOCLab Swarm service $sname"
      docker service rm "$sid" >/dev/null 2>&1 || true
    done
  fi

  deadline=$((SECONDS + 90))
  while (( SECONDS < deadline )); do
    local pending=0
    for net in shuffle_shuffle "$SHUFFLE_SWARM_NETWORK_NAME"; do
      docker network inspect "$net" >/dev/null 2>&1 || continue
      while read -r cid; do
        [[ -n "$cid" ]] || continue
        svc_label="$(docker inspect -f '{{index .Config.Labels "com.docker.swarm.service.name"}}' "$cid" 2>/dev/null || true)"
        if [[ -n "$svc_label" && "$svc_label" != "<no value>" ]]; then
          pending=1
          break
        fi
      done < <(docker ps -aq --filter "network=$net" 2>/dev/null || true)
      (( pending == 0 )) || break
    done
    (( pending == 0 )) && break
    sleep 2
  done

  for net in shuffle_shuffle "$SHUFFLE_SWARM_NETWORK_NAME"; do
    docker network inspect "$net" >/dev/null 2>&1 || continue
    while read -r cid; do
      [[ -n "$cid" ]] || continue
      cname="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##' || true)"
      case "$cname" in
        shuffle-frontend|shuffle-backend|shuffle-orborus|shuffle-opensearch) ;;
        *)
          log "Removing stale SOCLab runtime container ${cname:-$cid}"
          docker rm -f -v "$cid" >/dev/null 2>&1 || true
          ;;
      esac
    done < <(docker ps -aq --filter "network=$net" 2>/dev/null || true)
  done
}

remove_shuffle_execution_overlay_after_compose() {
  local deadline cid cname
  docker network inspect "$SHUFFLE_SWARM_NETWORK_NAME" >/dev/null 2>&1 || return 0

  deadline=$((SECONDS + 90))
  while (( SECONDS < deadline )); do
    while read -r cid; do
      [[ -n "$cid" ]] || continue
      cname="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##' || true)"
      log "Removing residual execution-network container ${cname:-$cid}"
      docker rm -f -v "$cid" >/dev/null 2>&1 || true
    done < <(docker ps -aq --filter "network=$SHUFFLE_SWARM_NETWORK_NAME" 2>/dev/null || true)

    docker network rm "$SHUFFLE_SWARM_NETWORK_NAME" >/dev/null 2>&1 && return 0
    sleep 2
  done

  warn "Residual endpoints on $SHUFFLE_SWARM_NETWORK_NAME:"
  docker network inspect -f '{{json .Containers}}' "$SHUFFLE_SWARM_NETWORK_NAME" 2>/dev/null || true
  die "Could not remove SOCLab execution overlay '$SHUFFLE_SWARM_NETWORK_NAME'."
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/credentials.sh
source "$SCRIPT_DIR/lib/credentials.sh"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/wazuh.sh
source "$SCRIPT_DIR/lib/wazuh.sh"
# shellcheck source=lib/wazuh_v3_certs.sh
source "$SCRIPT_DIR/lib/wazuh_v3_certs.sh"
# shellcheck source=lib/shuffle.sh
source "$SCRIPT_DIR/lib/shuffle.sh"
# shellcheck source=lib/healthcheck.sh
source "$SCRIPT_DIR/lib/healthcheck.sh"

reset_cmd() {
  need_root
  check_docker
  phase "RESET SOC LAB"
  quiesce_shuffle_for_cleanup
  remove_shuffle_swarm_services_before_compose
  clean_lab
  remove_shuffle_execution_overlay_after_compose
  ok "SOCLab reset complete; Docker Swarm mode itself was intentionally left unchanged"
}

install_all() {
  need_root
  check_docker

  phase "SOC LAB CLEAN INSTALL - WAZUH ${WAZUH_VERSION} + SHUFFLE ${SHUFFLE_VERSION} (SINGLE-NODE SWARM)"
  log "Shuffle execution architecture: one Docker Swarm manager+worker node with attachable overlay networks."
  log "This will erase ONLY the previous /opt/soclab, /opt/soar-lab, and SOCLab-owned Docker/Swarm runtime resources."

  preflight_shuffle_release

  quiesce_shuffle_for_cleanup
  remove_shuffle_swarm_services_before_compose
  clean_lab
  remove_shuffle_execution_overlay_after_compose

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
  verify_wazuh_cert_mounts
  configure_wazuh_api_runtime

  phase "PHASE 4/7 - START AND VERIFY WAZUH ${WAZUH_VERSION}"

  log "Starting Wazuh"
  if ! (cd "$WAZUH_SINGLE" && docker compose up -d --remove-orphans); then
    dump_wazuh_diagnostics
    die "docker compose up failed for Wazuh."
  fi

  wait_wazuh_service "wazuh.indexer" 480 || {
    dump_wazuh_diagnostics
    die "Wazuh indexer did not become healthy."
  }

  wait_wazuh_service "wazuh.manager" 420 || {
    dump_wazuh_diagnostics
    die "Wazuh manager did not become healthy."
  }

  wait_wazuh_service "wazuh.dashboard" 420 || {
    dump_wazuh_diagnostics
    die "Wazuh dashboard did not become healthy."
  }

  verify_wazuh_api_runtime_configuration

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
    code="$(curl -ksS -o /tmp/soclab-dashboard-http.out \
      -w '%{http_code}' --max-time 10 \
      "https://localhost:${WAZUH_DASHBOARD_PORT}/login" || true)"

    case "$code" in
      200|301|302|401|403)
        ok "Dashboard HTTPS endpoint reachable (HTTP $code)"
        break
        ;;
    esac

    if (( $(date +%s) - start >= 180 )); then
      dump_wazuh_diagnostics
      die "Wazuh dashboard /login did not return a valid HTTP response (last HTTP ${code:-none})."
    fi
    sleep 8
  done

  code="$(curl -ksS -o /tmp/soclab-indexer-http.out \
    -w '%{http_code}' --max-time 10 https://localhost:9200/ || true)"
  case "$code" in
    200|401|403) ok "Indexer HTTPS endpoint reachable (HTTP $code)" ;;
    *) dump_wazuh_diagnostics; die "Indexer HTTPS endpoint failed (HTTP ${code:-none})." ;;
  esac

  code="$(curl -ksS -o /tmp/soclab-wazuh-api-http.out \
    -w '%{http_code}' --max-time 10 "https://localhost:${WAZUH_API_PORT}/" || true)"
  case "$code" in
    200|401|403|404) ok "Wazuh API HTTPS listener reachable on TCP/${WAZUH_API_PORT} (HTTP $code)" ;;
    *) dump_wazuh_diagnostics; die "Wazuh API listener failed on TCP/${WAZUH_API_PORT} (HTTP ${code:-none})." ;;
  esac

  ok "WAZUH ${WAZUH_VERSION} PASSED ALL HEALTH GATES"

  install_shuffle
  final_health
  print_report
}

usage() {
  cat <<EOF
Usage: sudo ./install.sh <command>

Commands:
  install       Full clean install: Wazuh ${WAZUH_VERSION} + Shuffle ${SHUFFLE_VERSION} single-node Swarm
  healthcheck   Run reusable end-to-end healthcheck
  verify        Run the full local integration verification (alias of healthcheck)
  status        Show Compose, Swarm, network, and lab endpoint status
  logs [target] Show last 300 log lines; target: wazuh|shuffle|all
  reset         Remove only SOCLab-owned state, services and networks; leaves Swarm mode itself intact
  credentials   Show local mode-600 credential inventory path; does not print secrets
  help          Show this help

Environment overrides:
  SOCLAB_ROOT                    default: /opt/soclab
  WAZUH_DASHBOARD_PORT           default: 8443
  WAZUH_API_PORT                 default: 15500 (actual Wazuh API listener and host port)
  SHUFFLE_VERSION                default: 2.2.1
  SHUFFLE_FRONTEND_PORT          default: 3001
  SHUFFLE_HTTPS_PORT             default: 3443
  SHUFFLE_BACKEND_PORT           default: 5001
  SHUFFLE_OPENSEARCH_PORT        default: 9201
  SHUFFLE_SWARM_NETWORK_NAME     default: shuffle_swarm_executions
  SHUFFLE_SWARM_MTU              optional; set only when Docker/host MTU requires an override
  SOCLAB_SWARM_ADVERTISE_ADDR    optional; required only if docker swarm init cannot choose an address
EOF
}

dispatch() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    install) install_all "$@" ;;
    healthcheck|health|verify) healthcheck_all "$@" ;;
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
