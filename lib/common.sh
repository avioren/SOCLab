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

clean_lab() {
  phase "PHASE 1/7 - ERASE PREVIOUS SOC LAB"
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
  if [[ -d "$ROOT_DIR" ]]; then log "Deleting $ROOT_DIR"; rm -rf --one-file-system "$ROOT_DIR"; fi
  if [[ -d /opt/soar-lab ]]; then log "Deleting legacy /opt/soar-lab"; rm -rf --one-file-system /opt/soar-lab; fi
  mkdir -p "$ROOT_DIR" "$STATE_DIR"
  if docker ps -aq --filter 'label=com.docker.compose.project=single-node' | grep -q .; then die "Residual 'single-node' Compose containers remain after cleanup."; fi
  if docker ps -aq --filter 'label=com.docker.compose.project=shuffle' | grep -q .; then die "Residual 'shuffle' Compose containers remain after cleanup."; fi
  ok "Previous SOC lab state removed"
}
