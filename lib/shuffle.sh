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

patch_shuffle_compose() {
  local compose="$SHUFFLE_DIR/docker-compose.yml"

  python3 - "$compose" "$SHUFFLE_OPENSEARCH_PORT" <<'PY'
import pathlib, re, sys

p = pathlib.Path(sys.argv[1])
port = sys.argv[2]
text = p.read_text()

text = re.sub(
    r'(?m)^(\s*-\s*)"?9200:9200"?\s*$',
    rf'\1"127.0.0.1:{port}:9200"',
    text,
)
text = re.sub(
    r'(?m)^(\s*-\s*)"?0\.0\.0\.0:9200:9200"?\s*$',
    rf'\1"127.0.0.1:{port}:9200"',
    text,
)

p.write_text(text)
PY
}

install_shuffle() {
  phase "PHASE 5/7 - INSTALL SHUFFLE"

  log "Cloning Shuffle"
  git clone --depth 1 \
    https://github.com/Shuffle/Shuffle.git \
    "$SHUFFLE_DIR"

  [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]] || \
    die "Shuffle docker-compose.yml is missing."

  patch_shuffle_compose

  local env_file="$SHUFFLE_DIR/.env"
  touch "$env_file"
  chmod 600 "$env_file"

  local shuffle_pw encryption api_key
  shuffle_pw="$(openssl rand -base64 40 | tr -dc 'A-Za-z0-9' | head -c 28)"
  [[ ${#shuffle_pw} -ge 16 ]] || shuffle_pw="ShuffleLabAa1$(date +%s)"
  encryption="$(openssl rand -hex 32)"
  api_key="$(openssl rand -hex 32)"

  upsert_env "$env_file" "ENVIRONMENT_NAME" "Shuffle"
  upsert_env "$env_file" "FRONTEND_PORT" "$SHUFFLE_FRONTEND_PORT"
  upsert_env "$env_file" "FRONTEND_PORT_HTTPS" "$SHUFFLE_HTTPS_PORT"
  upsert_env "$env_file" "BACKEND_PORT" "$SHUFFLE_BACKEND_PORT"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_PORT" "$SHUFFLE_OPENSEARCH_PORT"
  upsert_env "$env_file" "OPENSEARCH_INITIAL_ADMIN_PASSWORD" "$shuffle_pw"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_PASSWORD" "$shuffle_pw"
  upsert_env "$env_file" "SHUFFLE_DEFAULT_USERNAME" "admin@soclab.local"
  upsert_env "$env_file" "SHUFFLE_DEFAULT_PASSWORD" "$shuffle_pw"
  upsert_env "$env_file" "SHUFFLE_DEFAULT_APIKEY" "$api_key"
  upsert_env "$env_file" "SHUFFLE_ENCRYPTION_MODIFIER" "$encryption"
  upsert_env "$env_file" "SHUFFLE_SKIPSSL_VERIFY" "true"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_SKIPSSL_VERIFY" "true"
  upsert_env "$env_file" "SHUFFLE_LOGS_DISABLED" "true"
  upsert_env "$env_file" "SHUFFLE_STATS_DISABLED" "true"
  upsert_env "$env_file" "TZ" "Asia/Jerusalem"

  mkdir -p \
    "$SHUFFLE_DIR/shuffle-database" \
    "$SHUFFLE_DIR/shuffle-apps" \
    "$SHUFFLE_DIR/shuffle-files"

  chown -R 1000:1000 "$SHUFFLE_DIR/shuffle-database" 2>/dev/null || true

  log "Validating Shuffle Compose configuration"
  (cd "$SHUFFLE_DIR" && docker compose config >/tmp/soclab-shuffle-compose.yml)

  log "Pulling Shuffle images"
  (cd "$SHUFFLE_DIR" && docker compose pull)

  log "Starting Shuffle"
  if ! (cd "$SHUFFLE_DIR" && docker compose up -d --remove-orphans); then
    (cd "$SHUFFLE_DIR" && docker compose ps -a && docker compose logs --tail 250) || true
    die "Shuffle docker compose up failed."
  fi

  local start
  start="$(date +%s)"
  while true; do
    if curl -fsS --max-time 10 \
        "http://localhost:${SHUFFLE_FRONTEND_PORT}/" >/dev/null 2>&1; then
      ok "Shuffle frontend reachable over HTTP"
      break
    fi

    if curl -kfsS --max-time 10 \
        "https://localhost:${SHUFFLE_HTTPS_PORT}/" >/dev/null 2>&1; then
      ok "Shuffle frontend reachable over HTTPS"
      break
    fi

    if (( $(date +%s) - start >= 480 )); then
      (cd "$SHUFFLE_DIR" && docker compose ps -a && docker compose logs --tail 300) || true
      die "Shuffle frontend failed its health gate."
    fi

    sleep 10
  done

  mkdir -p "$STATE_DIR"

  cat >"$STATE_DIR/credentials.txt" <<EOF
# SOC Lab runtime credential inventory - LOCAL FILE, NEVER COMMIT TO GIT
# Wazuh 5.0.0-beta5 is started with its upstream 5.x beta defaults unchanged.
# Shuffle upstream ships with no default UI account; this lab intentionally
# bootstraps a local admin account and a generated OpenSearch password.

WAZUH_VERSION=${WAZUH_VERSION}
WAZUH_DASHBOARD_URL=https://localhost:${WAZUH_DASHBOARD_PORT}
WAZUH_DASHBOARD_USERNAME=admin
WAZUH_DASHBOARD_PASSWORD=admin
WAZUH_INDEXER_URL=https://localhost:9200
WAZUH_INDEXER_USERNAME=admin
WAZUH_INDEXER_PASSWORD=admin
WAZUH_DASHBOARD_SERVICE_USERNAME=kibanaserver
WAZUH_DASHBOARD_SERVICE_PASSWORD=kibanaserver
WAZUH_API_URL=https://localhost:55000
WAZUH_API_USERNAME=wazuh
WAZUH_API_PASSWORD=wazuh
WAZUH_WUI_API_USERNAME=wazuh-wui
WAZUH_WUI_API_PASSWORD=wazuh-wui

SHUFFLE_URL=http://localhost:${SHUFFLE_FRONTEND_PORT}
SHUFFLE_UI_USERNAME=admin@soclab.local
SHUFFLE_UI_PASSWORD=${shuffle_pw}
SHUFFLE_API_KEY=${api_key}
SHUFFLE_OPENSEARCH_USERNAME=admin
SHUFFLE_OPENSEARCH_PASSWORD=${shuffle_pw}
SHUFFLE_UPSTREAM_UI_DEFAULT_ACCOUNT=none
EOF

  chmod 600 "$STATE_DIR/credentials.txt"

  ok "Runtime credential inventory written to $STATE_DIR/credentials.txt"
  ok "Shuffle passed frontend verification"
}
