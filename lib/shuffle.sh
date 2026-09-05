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
text = re.sub(r'(?m)^(\s*-\s*)"?9200:9200"?\s*$', rf'\1"127.0.0.1:{port}:9200"', text)
text = re.sub(r'(?m)^(\s*-\s*)"?0\.0\.0\.0:9200:9200"?\s*$', rf'\1"127.0.0.1:{port}:9200"', text)
p.write_text(text)
PY
}

install_shuffle() {
  phase "PHASE 5/7 - INSTALL SHUFFLE"
  log "Cloning Shuffle"
  git clone --depth 1 https://github.com/Shuffle/Shuffle.git "$SHUFFLE_DIR"
  [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]] || die "Shuffle docker-compose.yml is missing."
  patch_shuffle_compose

  local env_file="$SHUFFLE_DIR/.env"
  touch "$env_file"
  chmod 600 "$env_file"
  local shuffle_pw encryption api_key
  shuffle_pw="$SHUFFLE_OPENSEARCH_PASSWORD"
  encryption="$SHUFFLE_ENCRYPTION_MODIFIER"
  api_key="$SHUFFLE_API_KEY"

  upsert_env "$env_file" "ENVIRONMENT_NAME" "Shuffle"
  upsert_env "$env_file" "FRONTEND_PORT" "$SHUFFLE_FRONTEND_PORT"
  upsert_env "$env_file" "FRONTEND_PORT_HTTPS" "$SHUFFLE_HTTPS_PORT"
  upsert_env "$env_file" "BACKEND_PORT" "$SHUFFLE_BACKEND_PORT"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_PORT" "$SHUFFLE_OPENSEARCH_PORT"
  upsert_env "$env_file" "OPENSEARCH_INITIAL_ADMIN_PASSWORD" "$shuffle_pw"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_PASSWORD" "$shuffle_pw"
  upsert_env "$env_file" "SHUFFLE_DEFAULT_USERNAME" "$SHUFFLE_ADMIN_USERNAME"
  upsert_env "$env_file" "SHUFFLE_DEFAULT_PASSWORD" "$SHUFFLE_ADMIN_PASSWORD"
  upsert_env "$env_file" "SHUFFLE_DEFAULT_APIKEY" "$api_key"
  upsert_env "$env_file" "SHUFFLE_ENCRYPTION_MODIFIER" "$encryption"
  upsert_env "$env_file" "SHUFFLE_SKIPSSL_VERIFY" "true"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_SKIPSSL_VERIFY" "true"
  upsert_env "$env_file" "SHUFFLE_LOGS_DISABLED" "true"
  upsert_env "$env_file" "SHUFFLE_STATS_DISABLED" "true"
  upsert_env "$env_file" "TZ" "Asia/Jerusalem"

  mkdir -p "$SHUFFLE_DIR/shuffle-database" "$SHUFFLE_DIR/shuffle-apps" "$SHUFFLE_DIR/shuffle-files"
  chown -R 1000:1000 "$SHUFFLE_DIR/shuffle-database" 2>/dev/null || true

  log "Validating Shuffle Compose configuration"
  (cd "$SHUFFLE_DIR" && docker compose config --quiet)
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
    if curl -fsS --max-time 10 "http://localhost:${SHUFFLE_FRONTEND_PORT}/" >/dev/null 2>&1; then ok "Shuffle frontend reachable over HTTP"; break; fi
    if curl -kfsS --max-time 10 "https://localhost:${SHUFFLE_HTTPS_PORT}/" >/dev/null 2>&1; then ok "Shuffle frontend reachable over HTTPS"; break; fi
    if (( $(date +%s) - start >= 480 )); then
      (cd "$SHUFFLE_DIR" && docker compose ps -a && docker compose logs --tail 300) || true
      die "Shuffle frontend failed its health gate."
    fi
    sleep 10
  done
  ok "Shuffle passed frontend verification"
}
