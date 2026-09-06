#!/usr/bin/env bash
# shellcheck shell=bash

check_docker() {
  have docker || die "docker CLI not found. Enable Docker Desktop WSL integration first."
  docker version >/dev/null 2>&1 || die "Docker daemon is not reachable from this WSL distro."
  docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is unavailable."
  ok "Docker reachable. Context=$(docker context show 2>/dev/null || echo unknown)"
  log "Docker server: $(docker info --format '{{.OperatingSystem}}' 2>/dev/null || echo unknown)"
  log "Docker Compose: $(docker compose version --short 2>/dev/null || docker compose version)"
}

install_prereqs() {
  local pkgs=(git curl ca-certificates openssl jq python3 tar gzip sed grep gawk coreutils iproute2)
  local missing=() p
  for p in "${pkgs[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if (( ${#missing[@]} )); then
    log "Installing missing OS packages: ${missing[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends "${missing[@]}"
  else
    ok "OS prerequisites already installed"
  fi
}

check_resources() {
  mkdir -p "$ROOT_DIR"
  local cpu mem_gb free_gb
  cpu="$(nproc)"
  mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
  free_gb=$(( $(df -Pk "$ROOT_DIR" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
  log "Resources visible to WSL: CPU=${cpu}, RAM=${mem_gb}GiB, free=${free_gb}GiB"
  (( cpu >= 4 )) || die "Need at least 4 CPUs visible to WSL."
  (( mem_gb >= 8 )) || die "Need at least 8 GiB RAM visible to WSL."
  (( free_gb >= 50 )) || die "Need at least 50 GiB free for the Wazuh + Shuffle lab."
  ok "Resource check passed"
}

configure_host() {
  cat >/etc/sysctl.d/99-soclab-wazuh.conf <<'EOF'
vm.max_map_count=262144
fs.file-max=655360
EOF
  sysctl -w vm.max_map_count=262144 >/dev/null
  sysctl -w fs.file-max=655360 >/dev/null 2>&1 || true
  local mmc
  mmc="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
  (( mmc >= 262144 )) || die "vm.max_map_count did not apply correctly."
  ok "vm.max_map_count=$mmc"

  preflight_soclab_ports
}

soclab_application_port_contract() {
  # owner|bind_ip|host_port|protocol|container_port
  # Same container-internal port numbers are safe across separate network
  # namespaces. The host-side tuple (protocol, port) must be unique.
  cat <<EOF
Wazuh syslog|0.0.0.0|514|udp|514
Shuffle/Tenzir syslog|0.0.0.0|1514|tcp|1514
Wazuh enrollment|0.0.0.0|1515|tcp|1515
Wazuh agent events|0.0.0.0|${WAZUH_AGENT_PORT:-15140}|tcp|1514
Shuffle frontend HTTP compatibility|0.0.0.0|${SHUFFLE_FRONTEND_PORT:-3001}|tcp|80
Shuffle frontend HTTPS|0.0.0.0|${SHUFFLE_HTTPS_PORT:-3443}|tcp|443
Shuffle backend API|0.0.0.0|${SHUFFLE_BACKEND_PORT:-5001}|tcp|5001
Shuffle/Tenzir API|0.0.0.0|5160|tcp|5160
Wazuh dashboard|0.0.0.0|${WAZUH_DASHBOARD_PORT:-8443}|tcp|5601
Wazuh indexer|0.0.0.0|9200|tcp|9200
Shuffle OpenSearch|127.0.0.1|${SHUFFLE_OPENSEARCH_PORT:-9201}|tcp|9200
Wazuh API|127.0.0.1|${WAZUH_API_PORT:-15500}|tcp|${WAZUH_API_INTERNAL_PORT:-55000}
EOF
}

soclab_swarm_port_contract() {
  # owner|bind_ip|host_port|protocol|purpose
  cat <<'EOF'
Docker Swarm manager|0.0.0.0|2377|tcp|manager control plane
Docker Swarm gossip|0.0.0.0|7946|tcp|node discovery/communication
Docker Swarm gossip|0.0.0.0|7946|udp|node discovery/communication
Docker Swarm VXLAN|0.0.0.0|4789|udp|overlay data plane
EOF
}

validate_soclab_port_contract() {
  local owner bind port proto target key
  declare -A seen=()

  while IFS='|' read -r owner bind port proto target; do
    [[ -n "$owner" ]] || continue
    [[ "$port" =~ ^[0-9]+$ ]] || die "Invalid port '$port' in SOCLab port contract ($owner)."
    (( port >= 1 && port <= 65535 )) || die "Port $port is outside 1-65535 ($owner)."
    [[ "$proto" == tcp || "$proto" == udp ]] || die "Invalid protocol '$proto' for $owner."
    key="${proto}:${port}"
    if [[ -n "${seen[$key]:-}" ]]; then
      die "SOCLab port contract collision on $key: '$owner' conflicts with '${seen[$key]}'."
    fi
    seen[$key]="$owner"
  done < <(cat <(soclab_application_port_contract) <(soclab_swarm_port_contract))

  ok "Static port contract is collision-free across application and Swarm host ports"
}

dump_port_conflict_diagnostics() {
  local port="$1" proto="$2"
  warn "Port diagnostics for ${proto^^}/${port}:"

  if [[ "$proto" == tcp ]]; then
    ss -H -ltnp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" || true
  else
    ss -H -lunp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" || true
  fi

  echo "--- Docker published ports ---"
  docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null || true

  if have powershell.exe; then
    echo "--- Windows listener check ---"
    if [[ "$proto" == tcp ]]; then
      powershell.exe -NoProfile -NonInteractive -Command \
        "Get-NetTCPConnection -LocalPort ${port} -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,State,OwningProcess | Format-Table -AutoSize" \
        2>/dev/null | tr -d '\r' || true
    else
      powershell.exe -NoProfile -NonInteractive -Command \
        "Get-NetUDPEndpoint -LocalPort ${port} -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,OwningProcess | Format-Table -AutoSize" \
        2>/dev/null | tr -d '\r' || true
    fi
  fi

  if have cmd.exe; then
    echo "--- Windows excluded/reserved ${proto^^} ranges ---"
    cmd.exe /c "netsh interface ipv4 show excludedportrange protocol=${proto}" \
      2>/dev/null | tr -d '\r' || true
  fi
}

probe_soclab_application_ports() {
  local image="${SOCLAB_PORT_PROBE_IMAGE:-alpine:3.20}"
  local owner bind port proto container_port name output

  log "Pulling small Docker port-probe image: $image"
  docker pull "$image" >/dev/null 2>&1 || die "Could not pull $image for Docker Desktop port preflight."

  while IFS='|' read -r owner bind port proto container_port; do
    [[ -n "$owner" ]] || continue
    name="soclab-port-probe-${proto}-${port}"
    docker rm -f "$name" >/dev/null 2>&1 || true

    if ! output="$(docker run -d --rm --name "$name" \
        -p "${bind}:${port}:${container_port}/${proto}" \
        "$image" sh -c 'sleep 30' 2>&1)"; then
      warn "Docker Desktop failed to publish ${owner} on ${bind}:${port}/${proto}: $output"
      dump_port_conflict_diagnostics "$port" "$proto"
      die "Required host port ${port}/${proto} for '$owner' cannot be published. No SOCLab installation was started."
    fi

    docker rm -f "$name" >/dev/null 2>&1 || true
    ok "Port probe passed: ${bind}:${port}/${proto} -> ${owner}"
  done < <(soclab_application_port_contract)
}

probe_soclab_swarm_ports() {
  local owner bind port proto purpose
  local state
  state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"
  [[ "$state" != "active" ]] || die "Port preflight expected Swarm to be inactive after clean teardown; state=$state."

  while IFS='|' read -r owner bind port proto purpose; do
    [[ -n "$owner" ]] || continue
    if ! python3 - "$bind" "$port" "$proto" <<'PY'
import socket, sys
host, port, proto = sys.argv[1], int(sys.argv[2]), sys.argv[3]
kind = socket.SOCK_STREAM if proto == "tcp" else socket.SOCK_DGRAM
s = socket.socket(socket.AF_INET, kind)
try:
    s.bind((host, port))
    if proto == "tcp":
        s.listen(1)
finally:
    s.close()
PY
    then
      dump_port_conflict_diagnostics "$port" "$proto"
      die "Docker Swarm prerequisite ${port}/${proto} ($purpose) is already in use inside the Docker Linux host."
    fi
    ok "Swarm port probe passed: ${port}/${proto} ($purpose)"
  done < <(soclab_swarm_port_contract)
}

preflight_soclab_ports() {
  phase "PORT CONTRACT PREFLIGHT - WAZUH + SHUFFLE + TENZIR + SWARM"
  log "Wazuh API uses HTTPS internally on TCP/${WAZUH_API_INTERNAL_PORT:-55000}; host access is remapped to HTTPS TCP/${WAZUH_API_PORT:-15500}."
  validate_soclab_port_contract
  probe_soclab_swarm_ports
  probe_soclab_application_ports
  ok "All required SOCLab host ports are unique and bindable through the correct runtime layer"
}

remove_compose_project_resources() {
  local project="$1"
  local ids=() id
  mapfile -t ids < <(docker ps -aq --filter "label=com.docker.compose.project=${project}" 2>/dev/null || true)
  if (( ${#ids[@]} )); then
    log "Removing ${#ids[@]} container(s) belonging to Compose project '$project'"
    docker rm -f -v "${ids[@]}" >/dev/null 2>&1 || true
  fi
  mapfile -t ids < <(docker volume ls -q --filter "label=com.docker.compose.project=${project}" 2>/dev/null || true)
  if (( ${#ids[@]} )); then
    log "Removing ${#ids[@]} volume(s) belonging to Compose project '$project'"
    docker volume rm -f "${ids[@]}" >/dev/null 2>&1 || true
  fi
  mapfile -t ids < <(docker network ls -q --filter "label=com.docker.compose.project=${project}" 2>/dev/null || true)
  for id in "${ids[@]}"; do
    [[ -n "$id" ]] || continue
    log "Removing network $(docker network inspect -f '{{.Name}}' "$id" 2>/dev/null || echo "$id") from project '$project'"
    docker network rm "$id" >/dev/null 2>&1 || true
  done
}

remove_historical_exact_wazuh_names() {
  local c image
  for c in single-node-wazuh.indexer single-node-wazuh.manager single-node-wazuh.dashboard; do
    docker inspect "$c" >/dev/null 2>&1 || continue
    image="$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null || true)"
    if [[ "$image" == wazuh/* ]]; then
      log "Removing historical Wazuh lab container $c ($image)"
      docker rm -f -v "$c" >/dev/null 2>&1 || true
    else
      warn "Container $c exists but image is not wazuh/*; preserving it."
    fi
  done
}

validate_dedicated_single_node_swarm() {
  local state control nodes
  state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"
  [[ "$state" == "active" ]] || return 1

  control="$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || echo false)"
  [[ "$control" == "true" ]] || die "Docker Swarm is active but this host is not a manager; refusing destructive cleanup."

  docker node ls >/dev/null 2>&1 || die "Docker Swarm manager API is unavailable during cleanup."
  nodes="$(docker node ls -q | wc -l | tr -d ' ')"
  [[ "$nodes" == "1" ]] || die "SOCLab clean install may hard-reset only a dedicated one-node Swarm; found $nodes nodes."
  return 0
}

remove_all_single_node_swarm_services() {
  local deadline sid sname
  local -a services=() tasks=()

  validate_dedicated_single_node_swarm || return 0

  if docker inspect shuffle-orborus >/dev/null 2>&1; then
    log "Stopping Shuffle Orborus before Swarm reset"
    docker stop shuffle-orborus >/dev/null 2>&1 || true
  fi

  mapfile -t services < <(docker service ls -q 2>/dev/null || true)
  if (( ${#services[@]} )); then
    log "Dedicated one-node Swarm detected; removing ALL ${#services[@]} Swarm service(s) before clean install"
    for sid in "${services[@]}"; do
      sname="$(docker service inspect -f '{{.Spec.Name}}' "$sid" 2>/dev/null || echo "$sid")"
      log "Removing Swarm service $sname"
      docker service rm "$sid" >/dev/null 2>&1 || true
    done
  fi

  deadline=$((SECONDS + 120))
  while (( SECONDS < deadline )); do
    docker service ls -q 2>/dev/null | grep -q . || break
    sleep 2
  done
  if docker service ls -q 2>/dev/null | grep -q .; then
    warn "Residual Swarm services after removal attempt:"
    docker service ls 2>/dev/null || true
    die "Could not remove all services from the dedicated one-node Swarm."
  fi

  mapfile -t tasks < <(docker ps -aq --filter 'label=com.docker.swarm.service.name' 2>/dev/null || true)
  if (( ${#tasks[@]} )); then
    log "Removing ${#tasks[@]} residual Swarm task container(s)"
    docker rm -f -v "${tasks[@]}" >/dev/null 2>&1 || true
  fi
}

remove_tenzir_runtime() {
  local deadline cid cname

  if docker inspect tenzir-node >/dev/null 2>&1; then
    log "Removing SOCLab Tenzir runtime container tenzir-node"
    docker rm -f -v tenzir-node >/dev/null 2>&1 || die "Could not remove Tenzir runtime container 'tenzir-node'."
  fi

  if docker network inspect tenzir-network >/dev/null 2>&1; then
    while read -r cid; do
      [[ -n "$cid" ]] || continue
      cname="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##' || true)"
      log "Removing residual container ${cname:-$cid} from SOCLab Tenzir network"
      docker rm -f -v "$cid" >/dev/null 2>&1 || true
    done < <(docker ps -aq --filter 'network=tenzir-network' 2>/dev/null || true)

    deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do
      docker network inspect tenzir-network >/dev/null 2>&1 || break
      docker network rm tenzir-network >/dev/null 2>&1 || true
      sleep 1
    done
    if docker network inspect tenzir-network >/dev/null 2>&1; then
      die "Could not remove SOCLab Tenzir network 'tenzir-network'."
    fi
  fi

  if docker inspect tenzir-node >/dev/null 2>&1; then
    die "Residual Tenzir runtime container remains after cleanup."
  fi
  return 0
}

leave_dedicated_single_node_swarm() {
  local deadline state net
  validate_dedicated_single_node_swarm || return 0

  log "Leaving/resetting dedicated one-node Docker Swarm"
  docker swarm leave --force >/dev/null 2>&1 || die "docker swarm leave --force failed on dedicated one-node Swarm."

  deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"
    [[ "$state" != "active" ]] && break
    sleep 2
  done
  state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"
  [[ "$state" != "active" ]] || die "Docker remained in Swarm mode after forced single-node leave."

  for net in shuffle_shuffle "$SHUFFLE_SWARM_NETWORK_NAME"; do
    docker network inspect "$net" >/dev/null 2>&1 || continue
    log "Removing stale post-Swarm network $net"
    docker network rm "$net" >/dev/null 2>&1 || true
    docker network inspect "$net" >/dev/null 2>&1 && die "Network '$net' survived the dedicated Swarm reset."
  done

  ok "Dedicated one-node Swarm control plane reset; installer will initialize a fresh Swarm for Shuffle"
}

clean_lab() {
  phase "PHASE 1/7 - ERASE PREVIOUS SOC LAB"

  remove_all_single_node_swarm_services
  remove_tenzir_runtime

  if [[ -f "$WAZUH_SINGLE/docker-compose.yml" ]]; then
    log "Stopping existing Wazuh Compose project"
    (cd "$WAZUH_SINGLE" && docker compose down -v --remove-orphans --timeout 20) || true
  fi
  if [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]]; then
    log "Stopping existing Shuffle Compose project"
    (cd "$SHUFFLE_DIR" && docker compose down -v --remove-orphans --timeout 20) || true
  fi
  remove_compose_project_resources "single-node"
  remove_compose_project_resources "shuffle"
  remove_historical_exact_wazuh_names

  leave_dedicated_single_node_swarm

  if [[ -d "$ROOT_DIR" ]]; then log "Deleting $ROOT_DIR"; rm -rf --one-file-system "$ROOT_DIR"; fi
  if [[ -d /opt/soar-lab ]]; then log "Deleting legacy /opt/soar-lab"; rm -rf --one-file-system /opt/soar-lab; fi
  mkdir -p "$ROOT_DIR" "$STATE_DIR"
  if docker ps -aq --filter 'label=com.docker.compose.project=single-node' | grep -q .; then die "Residual 'single-node' Compose containers remain after cleanup."; fi
  if docker ps -aq --filter 'label=com.docker.compose.project=shuffle' | grep -q .; then die "Residual 'shuffle' Compose containers remain after cleanup."; fi
  if docker inspect tenzir-node >/dev/null 2>&1; then die "Residual Tenzir container remains after cleanup."; fi
  if docker network inspect tenzir-network >/dev/null 2>&1; then die "Residual Tenzir network remains after cleanup."; fi
  if docker service ls -q >/dev/null 2>&1; then
    docker service ls -q 2>/dev/null | grep -q . && die "Residual Swarm services remain after cleanup."
  fi
  ok "Previous SOC lab state removed; old single-node Swarm state cleared"
}
