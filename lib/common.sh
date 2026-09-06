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

  # Remove any orphaned task containers left by deleted services. This is what
  # prevents frikky/shuffle-tools and other Shuffle app tasks from appearing to
  # respawn during network cleanup.
  mapfile -t tasks < <(docker ps -aq --filter 'label=com.docker.swarm.service.name' 2>/dev/null || true)
  if (( ${#tasks[@]} )); then
    log "Removing ${#tasks[@]} residual Swarm task container(s)"
    docker rm -f -v "${tasks[@]}" >/dev/null 2>&1 || true
  fi
}

remove_tenzir_runtime() {
  local deadline cid cname

  # Tenzir is created by Shuffle/Orborus as a standalone container on its own
  # bridge network, so Swarm-service cleanup and Shuffle overlay cleanup do not
  # necessarily see it. Remove it explicitly after Orborus has been stopped.
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

  # The daemon should remove swarm-scoped overlays when leaving. If a named
  # SOCLab overlay remains locally, it no longer has a Swarm service reference
  # and can now be removed deterministically.
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

  # This lab intentionally owns its single-node Swarm. Remove the service
  # objects first (not their task containers) so Docker cannot respawn
  # shuffle-tools/app workers while Compose and overlays are being removed.
  remove_all_single_node_swarm_services

  # Tenzir is not a Swarm service; Orborus creates it as a standalone runtime
  # container on tenzir-network. Remove both explicitly before Compose/Swarm
  # teardown so it cannot survive a failed installation.
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

  # Compose containers are gone, so it is now safe to destroy the old
  # single-node Swarm metadata/overlay state. install_shuffle() later calls
  # ensure_shuffle_swarm_prereqs() and creates a fresh manager + ingress +
  # shuffle_swarm_executions overlay.
  leave_dedicated_single_node_swarm

  if [[ -d "$ROOT_DIR" ]]; then log "Deleting $ROOT_DIR"; rm -rf --one-file-system "$ROOT_DIR"; fi
  if [[ -d /opt/soar-lab ]]; then log "Deleting legacy /opt/soar-lab"; rm -rf --one-file-system /opt/soar-lab; fi
  mkdir -p "$ROOT_DIR" "$STATE_DIR"
  if docker ps -aq --filter 'label=com.docker.compose.project=single-node' | grep -q .; then die "Residual 'single-node' Compose containers remain after cleanup."; fi
  if docker ps -aq --filter 'label=com.docker.compose.project=shuffle' | grep -q .; then die "Residual 'shuffle' Compose containers remain after cleanup."; fi
  if docker inspect tenzir-node >/dev/null 2>&1; then die "Residual Tenzir container remains after cleanup."; fi
  if docker network inspect tenzir-network >/dev/null 2>&1; then die "Residual Tenzir network remains after cleanup."; fi
  if docker service ls -q >/dev/null 2>&1; then
    # docker service ls should no longer be available because Swarm was reset.
    docker service ls -q 2>/dev/null | grep -q . && die "Residual Swarm services remain after cleanup."
  fi
  ok "Previous SOC lab state removed; old single-node Swarm state cleared"
}
