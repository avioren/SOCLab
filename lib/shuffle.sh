#!/usr/bin/env bash
# shellcheck shell=bash

upsert_env() {
  local file="$1" key="$2" value="$3"
  touch "$file"

  if grep -qE "^${key}=" "$file"; then
    local escaped
    escaped="$(printf '%s' "$value" | sed 's/[&|]/\\&/g')"
    sed -i "s|^${key}=.*|${key}=${escaped}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

cleanup_shuffle_swarm_runtime() {
  local state net_id sid sname image deadline
  state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"

  if docker inspect shuffle-orborus >/dev/null 2>&1; then
    docker stop shuffle-orborus >/dev/null 2>&1 || true
  fi

  if [[ "$state" == "active" ]] && docker node ls >/dev/null 2>&1; then
    if docker service inspect shuffle-workers >/dev/null 2>&1; then
      log "Removing previous SOCLab shuffle-workers service"
      docker service rm shuffle-workers >/dev/null 2>&1 || true
    fi

    net_id="$(docker network inspect -f '{{.Id}}' "$SHUFFLE_SWARM_NETWORK_NAME" 2>/dev/null || true)"
    if [[ -n "$net_id" ]]; then
      while read -r sid; do
        [[ -n "$sid" ]] || continue
        if docker service inspect -f '{{range .Spec.TaskTemplate.Networks}}{{println .Target}}{{end}}' "$sid" 2>/dev/null |
            grep -qx "$net_id"; then
          sname="$(docker service inspect -f '{{.Spec.Name}}' "$sid" 2>/dev/null || echo "$sid")"
          log "Removing previous SOCLab execution service $sname"
          docker service rm "$sid" >/dev/null 2>&1 || true
        fi
      done < <(docker service ls -q 2>/dev/null || true)

      deadline=$((SECONDS + 30))
      while (( SECONDS < deadline )); do
        docker network inspect "$SHUFFLE_SWARM_NETWORK_NAME" >/dev/null 2>&1 || break
        docker network rm "$SHUFFLE_SWARM_NETWORK_NAME" >/dev/null 2>&1 && break
        sleep 2
      done
    fi
  fi

  if docker inspect tenzir-node >/dev/null 2>&1; then
    image="$(docker inspect -f '{{.Config.Image}}' tenzir-node 2>/dev/null || true)"
    if [[ "$image" == *shuffle*tenzir* || "$image" == *tenzir* ]]; then
      log "Removing stale SOCLab Tenzir runtime container"
      docker rm -f -v tenzir-node >/dev/null 2>&1 || true
    fi
  fi

  if docker service inspect shuffle-workers >/dev/null 2>&1; then
    die "Residual shuffle-workers service remains after SOCLab cleanup."
  fi
  if docker network inspect "$SHUFFLE_SWARM_NETWORK_NAME" >/dev/null 2>&1; then
    die "Residual execution overlay '$SHUFFLE_SWARM_NETWORK_NAME' remains after SOCLab cleanup."
  fi
}

generate_shuffle_opensearch_password() {
  python3 - <<'PY'
import secrets
alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@%_-"
required = [
    secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ"),
    secrets.choice("abcdefghijkmnopqrstuvwxyz"),
    secrets.choice("23456789"),
    secrets.choice("!@%_-"),
]
chars = required + [secrets.choice(alphabet) for _ in range(28)]
secrets.SystemRandom().shuffle(chars)
print("".join(chars))
PY
}

preflight_shuffle_release() {
  phase "PREFLIGHT - SHUFFLE ${SHUFFLE_VERSION} RELEASE ARTIFACTS"

  git ls-remote --exit-code --refs --tags \
    https://github.com/Shuffle/Shuffle.git "refs/tags/${SHUFFLE_REF}" \
    >/dev/null 2>&1 || die "Shuffle source tag ${SHUFFLE_REF} is not available."

  local image
  for image in \
    "$SHUFFLE_FRONTEND_IMAGE" \
    "$SHUFFLE_BACKEND_IMAGE" \
    "$SHUFFLE_ORBORUS_IMAGE" \
    "$SHUFFLE_WORKER_IMAGE" \
    "$SHUFFLE_OPENSEARCH_IMAGE"; do
    log "Checking image manifest: $image"
    docker manifest inspect "$image" >/dev/null 2>&1 || \
      die "Required image tag is unavailable: $image"
  done

  ok "Pinned Shuffle ${SHUFFLE_VERSION} source and image manifests are available"
}

ensure_shuffle_swarm_prereqs() {
  phase "SHUFFLE SWARM PREREQUISITES"

  cat >/etc/sysctl.d/99-soclab-shuffle-swarm.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" == "1" ]] ||
    die "net.ipv4.ip_forward must be 1 for Shuffle Swarm networking."

  local state control nodes availability
  state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"

  if [[ "$state" != "active" ]]; then
    log "Docker Swarm is not active; initializing a single-node Swarm"
    if [[ -n "$SOCLAB_SWARM_ADVERTISE_ADDR" ]]; then
      docker swarm init --advertise-addr "$SOCLAB_SWARM_ADVERTISE_ADDR" >/dev/null || \
        die "docker swarm init failed with SOCLAB_SWARM_ADVERTISE_ADDR=$SOCLAB_SWARM_ADVERTISE_ADDR"
    else
      if ! docker swarm init >/tmp/soclab-swarm-init.out 2>&1; then
        cat /tmp/soclab-swarm-init.out >&2 || true
        die "docker swarm init failed. If Docker cannot choose an address, rerun with SOCLAB_SWARM_ADVERTISE_ADDR=<manager-address>."
      fi
    fi
  fi

  state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo unknown)"
  control="$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || echo false)"
  [[ "$state" == "active" ]] || die "Docker Swarm did not become active."
  [[ "$control" == "true" ]] || die "SOCLab requires this one server to be a Swarm manager."

  docker node ls >/dev/null 2>&1 || die "Docker Swarm manager API is not available."
  nodes="$(docker node ls -q | wc -l | tr -d ' ')"
  [[ "$nodes" == "1" ]] || \
    die "SOCLab single-server profile requires exactly one Swarm node; found $nodes. Refusing to modify an existing multi-node Swarm."

  availability="$(docker node inspect self --format '{{.Spec.Availability}}' 2>/dev/null || echo unknown)"
  [[ "$availability" == "active" ]] || die "Local Swarm node availability is '$availability', expected 'active'."

  if ! docker network inspect ingress >/dev/null 2>&1; then
    die "Swarm ingress overlay is missing after initialization."
  fi
  [[ "$(docker network inspect -f '{{.Driver}}' ingress 2>/dev/null)" == "overlay" ]] || \
    die "Swarm ingress network is not an overlay network."

  ensure_shuffle_execution_network

  ok "Single-node Docker Swarm manager is active and execution overlay is ready"
}

ensure_shuffle_execution_network() {
  local driver scope attachable
  if ! docker network inspect "$SHUFFLE_SWARM_NETWORK_NAME" >/dev/null 2>&1; then
    log "Creating attachable Shuffle execution overlay: $SHUFFLE_SWARM_NETWORK_NAME"
    if [[ -n "$SHUFFLE_SWARM_MTU" ]]; then
      [[ "$SHUFFLE_SWARM_MTU" =~ ^[0-9]+$ ]] || die "SHUFFLE_SWARM_MTU must be numeric."
      docker network create \
        --driver overlay \
        --attachable \
        --opt "com.docker.network.driver.mtu=${SHUFFLE_SWARM_MTU}" \
        "$SHUFFLE_SWARM_NETWORK_NAME" >/dev/null
    else
      docker network create \
        --driver overlay \
        --attachable \
        "$SHUFFLE_SWARM_NETWORK_NAME" >/dev/null
    fi
  fi

  driver="$(docker network inspect -f '{{.Driver}}' "$SHUFFLE_SWARM_NETWORK_NAME" 2>/dev/null || echo unknown)"
  scope="$(docker network inspect -f '{{.Scope}}' "$SHUFFLE_SWARM_NETWORK_NAME" 2>/dev/null || echo unknown)"
  attachable="$(docker network inspect -f '{{.Attachable}}' "$SHUFFLE_SWARM_NETWORK_NAME" 2>/dev/null || echo false)"
  [[ "$driver" == "overlay" ]] || die "$SHUFFLE_SWARM_NETWORK_NAME driver is '$driver', expected overlay."
  [[ "$scope" == "swarm" ]] || die "$SHUFFLE_SWARM_NETWORK_NAME scope is '$scope', expected swarm."
  [[ "$attachable" == "true" ]] || die "$SHUFFLE_SWARM_NETWORK_NAME is not attachable."
}

patch_shuffle_compose() {
  local compose="$SHUFFLE_DIR/docker-compose.yml"

  python3 - \
    "$compose" \
    "$SHUFFLE_OPENSEARCH_PORT" \
    "$SHUFFLE_FRONTEND_IMAGE" \
    "$SHUFFLE_BACKEND_IMAGE" \
    "$SHUFFLE_ORBORUS_IMAGE" \
    "$SHUFFLE_WORKER_IMAGE" \
    "$SHUFFLE_OPENSEARCH_IMAGE" \
    "$SHUFFLE_SWARM_MTU" <<'PY'
import pathlib, re, sys

(
    compose_path,
    os_port,
    frontend_image,
    backend_image,
    orborus_image,
    worker_image,
    opensearch_image,
    swarm_mtu,
) = sys.argv[1:]

p = pathlib.Path(compose_path)
text = p.read_text()

def sub_required(pattern, replacement, data, label, flags=0):
    new, count = re.subn(pattern, replacement, data, flags=flags)
    if count == 0:
        raise SystemExit(f"Could not patch Shuffle compose: {label}")
    return new

text = sub_required(
    r'(?m)^(\s*image:\s*)ghcr\.io/shuffle/shuffle-frontend:[^\s]+$',
    rf'\1{frontend_image}', text, "frontend image")
text = sub_required(
    r'(?m)^(\s*image:\s*)ghcr\.io/shuffle/shuffle-backend:[^\s]+$',
    rf'\1{backend_image}', text, "backend image")
text = sub_required(
    r'(?m)^(\s*image:\s*)ghcr\.io/shuffle/shuffle-orborus:[^\s]+$',
    rf'\1{orborus_image}', text, "orborus image")
text = sub_required(
    r'(?m)^(\s*-\s*SHUFFLE_WORKER_IMAGE=)ghcr\.io/shuffle/shuffle-worker:[^\s]+$',
    rf'\1{worker_image}', text, "worker image")
text = sub_required(
    r'(?m)^(\s*image:\s*)opensearchproject/opensearch:[^\s]+$',
    rf'\1{opensearch_image}', text, "OpenSearch image")

text = sub_required(
    r'(?m)^(\s*-\s*)"?9200:9200"?\s*$',
    rf'\1"127.0.0.1:{os_port}:9200"', text, "OpenSearch host port")

text = sub_required(
    r'(?m)^(\s*-\s*CLEANUP=)false\s*$', r'\1true', text, "Orborus cleanup mode")

def add_execution_network_to_service(data, service, next_service):
    pattern = rf'(?ms)(^  {re.escape(service)}:\n.*?)(?=^  {re.escape(next_service)}:)'
    match = re.search(pattern, data)
    if not match:
        raise SystemExit(f"Could not locate {service} service block")
    block = match.group(1)
    if "      - swarm_executions\n" not in block:
        block, count = re.subn(
            r'(?m)^    networks:\n      - shuffle\s*$',
            '    networks:\n      - shuffle\n      - swarm_executions', block, count=1)
        if count == 0:
            raise SystemExit(f"Could not attach {service} to execution overlay")
    return data[:match.start(1)] + block + data[match.end(1):]

text = add_execution_network_to_service(text, "backend", "orborus")
text = add_execution_network_to_service(text, "orborus", "opensearch")

core_network = """networks:
  shuffle:
    driver: overlay
    attachable: true
"""
if swarm_mtu:
    core_network += f"""    driver_opts:
      com.docker.network.driver.mtu: \"{swarm_mtu}\"
"""
core_network += """  swarm_executions:
    external: true
    name: ${SHUFFLE_SWARM_NETWORK_NAME}
"""

text = sub_required(
    r'(?ms)^networks:\n  shuffle:\n.*\Z', core_network, text, "network definitions")
p.write_text(text)
PY

  grep -qF "image: $SHUFFLE_FRONTEND_IMAGE" "$compose" || die "Frontend image pin missing after patch."
  grep -qF "image: $SHUFFLE_BACKEND_IMAGE" "$compose" || die "Backend image pin missing after patch."
  grep -qF "image: $SHUFFLE_ORBORUS_IMAGE" "$compose" || die "Orborus image pin missing after patch."
  grep -qF "SHUFFLE_WORKER_IMAGE=$SHUFFLE_WORKER_IMAGE" "$compose" || die "Worker image pin missing after patch."
  grep -qF "driver: overlay" "$compose" || die "Shuffle core overlay patch missing."
  grep -qF 'name: ${SHUFFLE_SWARM_NETWORK_NAME}' "$compose" || die "Execution overlay declaration missing."
  grep -qF "CLEANUP=true" "$compose" || die "Orborus cleanup mode was not enabled."
}

detect_shuffle_opensearch_image_account() {
  local out uid gid
  out="$(
    docker run --rm --entrypoint sh "$SHUFFLE_OPENSEARCH_IMAGE" -lc \
      'u=$(id -u opensearch 2>/dev/null || id -u); g=$(id -g opensearch 2>/dev/null || id -g); printf "%s:%s\n" "$u" "$g"'
  )" || die "Could not determine UID/GID for Shuffle OpenSearch image $SHUFFLE_OPENSEARCH_IMAGE"

  uid="${out%%:*}"
  gid="${out##*:}"
  [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || \
    die "Unexpected Shuffle OpenSearch UID/GID result: $out"

  SHUFFLE_OPENSEARCH_UID="$uid"
  SHUFFLE_OPENSEARCH_GID="$gid"
  log "Shuffle OpenSearch image account: ${uid}:${gid}"
}

shuffle_core_network_name() {
  printf '%s\n' "shuffle_shuffle"
}

verify_shuffle_overlay_topology() {
  local core driver scope attachable
  core="$(shuffle_core_network_name)"

  for net in "$core" "$SHUFFLE_SWARM_NETWORK_NAME"; do
    docker network inspect "$net" >/dev/null 2>&1 || return 1
    driver="$(docker network inspect -f '{{.Driver}}' "$net" 2>/dev/null || echo unknown)"
    scope="$(docker network inspect -f '{{.Scope}}' "$net" 2>/dev/null || echo unknown)"
    attachable="$(docker network inspect -f '{{.Attachable}}' "$net" 2>/dev/null || echo false)"
    [[ "$driver" == "overlay" && "$scope" == "swarm" && "$attachable" == "true" ]] || return 1
  done

  docker inspect -f '{{json .NetworkSettings.Networks}}' shuffle-backend 2>/dev/null |
    grep -q "\"${SHUFFLE_SWARM_NETWORK_NAME}\"" || return 1
  docker inspect -f '{{json .NetworkSettings.Networks}}' shuffle-orborus 2>/dev/null |
    grep -q "\"${SHUFFLE_SWARM_NETWORK_NAME}\"" || return 1
}

wait_shuffle_worker_service() {
  local timeout="${1:-300}"
  local deadline replicas image net_id mounts
  deadline=$((SECONDS + timeout))
  net_id="$(docker network inspect -f '{{.Id}}' "$SHUFFLE_SWARM_NETWORK_NAME" 2>/dev/null || true)"

  while (( SECONDS < deadline )); do
    if docker service inspect shuffle-workers >/dev/null 2>&1; then
      replicas="$(docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null | awk '$1 == "shuffle-workers" {print $2; exit}')"
      if [[ "$replicas" == "1/1" ]]; then
        image="$(docker service inspect -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' shuffle-workers 2>/dev/null || true)"
        [[ "$image" == "$SHUFFLE_WORKER_IMAGE"* ]] || {
          warn "shuffle-workers image '$image' does not match $SHUFFLE_WORKER_IMAGE"
          return 1
        }

        if [[ -n "$net_id" ]]; then
          docker service inspect -f '{{range .Spec.TaskTemplate.Networks}}{{println .Target}}{{end}}' shuffle-workers 2>/dev/null |
            grep -qx "$net_id" || {
              warn "shuffle-workers is not attached to $SHUFFLE_SWARM_NETWORK_NAME"
              return 1
            }
        fi

        mounts="$(docker service inspect -f '{{json .Spec.TaskTemplate.ContainerSpec.Mounts}}' shuffle-workers 2>/dev/null || true)"
        if [[ "$mounts" != *"/var/run/docker.sock"* ]]; then
          warn "shuffle-workers does not have Docker manager socket access"
          return 1
        fi

        ok "Shuffle worker Swarm service is ready (1/1, pinned image, execution overlay, Docker socket)"
        return 0
      fi
    fi
    sleep 5
  done
  return 1
}

verify_shuffle_backend_db() {
  local code
  code="$(curl -s -o /tmp/soclab-shuffle-checkusers.out -w '%{http_code}' --max-time 15 \
    "http://localhost:${SHUFFLE_BACKEND_PORT}/api/v1/checkusers" 2>/dev/null || true)"
  [[ "$code" == "200" ]]
}

verify_shuffle_opensearch() {
  local password="$1" code health
  code="$(curl -ks -u "admin:${password}" -o /tmp/soclab-shuffle-os.out -w '%{http_code}' --max-time 15 \
    "https://localhost:${SHUFFLE_OPENSEARCH_PORT}/_cluster/health" 2>/dev/null || true)"
  [[ "$code" == "200" ]] || return 1
  health="$(jq -r '.status // empty' /tmp/soclab-shuffle-os.out 2>/dev/null || true)"
  [[ "$health" == "green" || "$health" == "yellow" ]]
}

dump_shuffle_diagnostics() {
  echo "===== SHUFFLE COMPOSE ====="
  if [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]]; then
    (cd "$SHUFFLE_DIR" && docker compose ps -a) || true
    (cd "$SHUFFLE_DIR" && docker compose logs --tail 250) || true
  fi
  echo "===== SWARM ====="
  docker info --format 'State={{.Swarm.LocalNodeState}} Control={{.Swarm.ControlAvailable}}' 2>/dev/null || true
  docker node ls 2>/dev/null || true
  docker network ls 2>/dev/null || true
  if docker service inspect shuffle-workers >/dev/null 2>&1; then
    docker service ps --no-trunc shuffle-workers 2>/dev/null || true
  fi
}

install_shuffle() {
  phase "PHASE 5/7 - INSTALL SHUFFLE ${SHUFFLE_VERSION} SINGLE-NODE SWARM"

  ensure_shuffle_swarm_prereqs

  log "Cloning pinned Shuffle ${SHUFFLE_REF}"
  git clone --depth 1 --branch "$SHUFFLE_REF" \
    https://github.com/Shuffle/Shuffle.git "$SHUFFLE_DIR"

  [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]] || die "Shuffle docker-compose.yml is missing."
  patch_shuffle_compose

  local env_file="$SHUFFLE_DIR/.env"
  touch "$env_file"
  chmod 600 "$env_file"

  local shuffle_pw encryption api_key
  shuffle_pw="$(generate_shuffle_opensearch_password)"
  encryption="$(openssl rand -hex 32)"
  api_key="$(openssl rand -hex 32)"

  upsert_env "$env_file" "ENVIRONMENT_NAME" "Shuffle"
  upsert_env "$env_file" "FRONTEND_PORT" "$SHUFFLE_FRONTEND_PORT"
  upsert_env "$env_file" "FRONTEND_PORT_HTTPS" "$SHUFFLE_HTTPS_PORT"
  upsert_env "$env_file" "BACKEND_PORT" "$SHUFFLE_BACKEND_PORT"
  upsert_env "$env_file" "BACKEND_HOSTNAME" "shuffle-backend"
  upsert_env "$env_file" "BASE_URL" "http://shuffle-backend:5001"
  upsert_env "$env_file" "OUTER_HOSTNAME" "shuffle-backend"
  upsert_env "$env_file" "DB_LOCATION" "$SHUFFLE_DIR/shuffle-database"
  upsert_env "$env_file" "SHUFFLE_APP_HOTLOAD_FOLDER" "/shuffle-apps"
  upsert_env "$env_file" "SHUFFLE_APP_HOTLOAD_LOCATION" "$SHUFFLE_DIR/shuffle-apps"
  upsert_env "$env_file" "SHUFFLE_FILE_LOCATION" "$SHUFFLE_DIR/shuffle-files"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_URL" "https://shuffle-opensearch:9200"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_USERNAME" "admin"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_PASSWORD" "$shuffle_pw"
  upsert_env "$env_file" "OPENSEARCH_INITIAL_ADMIN_PASSWORD" "$shuffle_pw"
  upsert_env "$env_file" "SHUFFLE_DEFAULT_USERNAME" "admin@soclab.local"
  upsert_env "$env_file" "SHUFFLE_DEFAULT_PASSWORD" "$shuffle_pw"
  upsert_env "$env_file" "SHUFFLE_DEFAULT_APIKEY" "$api_key"
  upsert_env "$env_file" "SHUFFLE_ENCRYPTION_MODIFIER" "$encryption"
  upsert_env "$env_file" "SHUFFLE_SKIPSSL_VERIFY" "true"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_SKIPSSL_VERIFY" "true"
  upsert_env "$env_file" "SHUFFLE_LOGS_DISABLED" "true"
  upsert_env "$env_file" "SHUFFLE_STATS_DISABLED" "true"
  upsert_env "$env_file" "SHUFFLE_SWARM_CONFIG" "run"
  upsert_env "$env_file" "SHUFFLE_SWARM_NETWORK_NAME" "$SHUFFLE_SWARM_NETWORK_NAME"
  upsert_env "$env_file" "SHUFFLE_WORKER_IMAGE" "$SHUFFLE_WORKER_IMAGE"
  upsert_env "$env_file" "SHUFFLE_WORKER_SERVER_URL" "http://shuffle-workers:33333"
  upsert_env "$env_file" "SHUFFLE_SCALE_REPLICAS" "1"
  upsert_env "$env_file" "SHUFFLE_APP_REPLICAS" "1"
  upsert_env "$env_file" "SHUFFLE_MAX_SWARM_NODES" "1"
  upsert_env "$env_file" "SHUFFLE_CONTAINER_AUTO_CLEANUP" "true"
  upsert_env "$env_file" "SHUFFLE_ORBORUS_EXECUTION_CONCURRENCY" "5"
  upsert_env "$env_file" "ORBORUS_CONTAINER_NAME" "shuffle-orborus"
  upsert_env "$env_file" "SHUFFLE_SWARM_BRIDGE_DEFAULT_INTERFACE" "eth0"
  upsert_env "$env_file" "TZ" "Asia/Jerusalem"
  if [[ -n "$SHUFFLE_SWARM_MTU" ]]; then
    upsert_env "$env_file" "SHUFFLE_SWARM_BRIDGE_DEFAULT_MTU" "$SHUFFLE_SWARM_MTU"
  fi

  mkdir -p "$SHUFFLE_DIR/shuffle-database" "$SHUFFLE_DIR/shuffle-apps" "$SHUFFLE_DIR/shuffle-files"

  log "Validating patched Shuffle Compose configuration without rendering secrets"
  (cd "$SHUFFLE_DIR" && docker compose config --quiet)

  log "Pulling pinned Shuffle core images"
  (cd "$SHUFFLE_DIR" && docker compose pull)
  docker pull "$SHUFFLE_WORKER_IMAGE" >/dev/null

  detect_shuffle_opensearch_image_account
  chown -R "${SHUFFLE_OPENSEARCH_UID}:${SHUFFLE_OPENSEARCH_GID}" "$SHUFFLE_DIR/shuffle-database"
  chmod 0750 "$SHUFFLE_DIR/shuffle-database"

  log "Starting Shuffle core containers on Swarm overlay networks"
  if ! (cd "$SHUFFLE_DIR" && docker compose up -d --remove-orphans); then
    dump_shuffle_diagnostics
    die "Shuffle docker compose up failed."
  fi

  local deadline=$((SECONDS + 480))
  while (( SECONDS < deadline )); do
    if verify_shuffle_opensearch "$shuffle_pw" && verify_shuffle_backend_db; then
      break
    fi
    sleep 8
  done
  if ! verify_shuffle_opensearch "$shuffle_pw" || ! verify_shuffle_backend_db; then
    dump_shuffle_diagnostics
    die "Shuffle OpenSearch/backend datastore health gate failed."
  fi
  ok "Shuffle OpenSearch and backend datastore/API path are healthy"

  if ! verify_shuffle_overlay_topology; then
    dump_shuffle_diagnostics
    die "Shuffle overlay topology is inconsistent."
  fi
  ok "Shuffle core and execution overlay topology verified"

  if ! curl -fsS --max-time 10 "http://localhost:${SHUFFLE_FRONTEND_PORT}/" >/dev/null 2>&1 &&
     ! curl -kfsS --max-time 10 "https://localhost:${SHUFFLE_HTTPS_PORT}/" >/dev/null 2>&1; then
    dump_shuffle_diagnostics
    die "Shuffle frontend is not reachable."
  fi
  ok "Shuffle frontend is reachable"

  if ! wait_shuffle_worker_service 300; then
    dump_shuffle_diagnostics
    die "Shuffle Orborus did not establish a healthy 1/1 shuffle-workers Swarm service."
  fi

  if docker logs --since 2m shuffle-orborus 2>&1 |
      grep -Eq 'network .* not found|Failed to start .*container networking|shuffle-workers.*no such host'; then
    dump_shuffle_diagnostics
    die "Recent Orborus logs contain an execution-network/worker bootstrap failure."
  fi

  mkdir -p "$STATE_DIR"
  cat >"$STATE_DIR/credentials.txt" <<EOF
# SOC Lab runtime credential inventory - LOCAL FILE, NEVER COMMIT TO GIT
# Written only after Shuffle control/data/execution health gates pass.
WAZUH_VERSION=${WAZUH_VERSION}
WAZUH_DASHBOARD_URL=https://localhost:${WAZUH_DASHBOARD_PORT}
WAZUH_DASHBOARD_USERNAME=admin
WAZUH_DASHBOARD_PASSWORD=admin
WAZUH_INDEXER_URL=https://localhost:9200
WAZUH_INDEXER_USERNAME=admin
WAZUH_INDEXER_PASSWORD=admin
WAZUH_DASHBOARD_SERVICE_USERNAME=kibanaserver
WAZUH_DASHBOARD_SERVICE_PASSWORD=kibanaserver
WAZUH_API_URL=https://localhost:${WAZUH_API_PORT}
WAZUH_API_USERNAME=wazuh
WAZUH_API_PASSWORD=wazuh
WAZUH_WUI_API_USERNAME=wazuh-wui
WAZUH_WUI_API_PASSWORD=wazuh-wui

SHUFFLE_VERSION=${SHUFFLE_VERSION}
SHUFFLE_URL=http://localhost:${SHUFFLE_FRONTEND_PORT}
SHUFFLE_UI_USERNAME=admin@soclab.local
SHUFFLE_UI_PASSWORD=${shuffle_pw}
SHUFFLE_API_KEY=${api_key}
SHUFFLE_OPENSEARCH_USERNAME=admin
SHUFFLE_OPENSEARCH_PASSWORD=${shuffle_pw}
SHUFFLE_SWARM_NETWORK_NAME=${SHUFFLE_SWARM_NETWORK_NAME}
SHUFFLE_UPSTREAM_UI_DEFAULT_ACCOUNT=none
EOF
  chmod 600 "$STATE_DIR/credentials.txt"

  ok "Runtime credential inventory written to $STATE_DIR/credentials.txt"
  ok "Shuffle ${SHUFFLE_VERSION} single-node Swarm passed control/data/execution health gates"
}
