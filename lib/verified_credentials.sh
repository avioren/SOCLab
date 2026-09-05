#!/usr/bin/env bash
# shellcheck shell=bash
# Runtime verification and stock Shuffle installation.

json_login_payload() {
  local username="$1" password="$2"
  LOGIN_USERNAME="$username" LOGIN_PASSWORD="$password" python3 - <<'PY'
import json, os
print(json.dumps({"username": os.environ["LOGIN_USERNAME"], "password": os.environ["LOGIN_PASSWORD"]}))
PY
}

wazuh_dashboard_login_ok() {
  local username="$1" password="$2" base="https://localhost:${WAZUH_DASHBOARD_PORT}"
  local payload response cookie code endpoint
  payload="$(json_login_payload "$username" "$password")"
  response="$(mktemp /tmp/soclab-wazuh-ui-response.XXXXXX)"
  cookie="$(mktemp /tmp/soclab-wazuh-ui-cookie.XXXXXX)"
  chmod 600 "$response" "$cookie"

  for endpoint in '/auth/login?dataSourceId=' '/auth/login'; do
    code="$(printf '%s' "$payload" | curl -ksS --max-time 15 \
      -c "$cookie" -o "$response" -w '%{http_code}' \
      -H 'Content-Type: application/json' \
      -H 'osd-xsrf: osd-fetch' \
      --data-binary @- "${base}${endpoint}" || true)"
    if [[ "$code" == "200" ]]; then
      rm -f "$response" "$cookie"
      unset payload
      return 0
    fi
  done

  rm -f "$response" "$cookie"
  unset payload
  return 1
}

verify_runtime_credentials() {
  local code token
  code="$(curl -ksS -o /tmp/soclab-admin-auth.out -w '%{http_code}' --max-time 10 \
    -u "${WAZUH_ADMIN_USER}:${WAZUH_ADMIN_PASSWORD}" https://localhost:9200/ || true)"
  [[ "$code" == "200" ]] || die "Stock Wazuh admin/indexer credential verification failed (HTTP ${code:-none})."
  ok "Stock Wazuh admin/indexer credential authenticated successfully"

  if [[ -n "${WAZUH_API_PASSWORD:-}" ]]; then
    token="$(curl -ksS --max-time 15 -u "${WAZUH_API_USER}:${WAZUH_API_PASSWORD}" \
      -X POST 'https://localhost:55000/security/user/authenticate?raw=true' || true)"
    [[ -n "$token" && "$token" != *'error'* && "$token" != *'Unauthorized'* ]] || \
      die "Stock Wazuh API credential verification failed for ${WAZUH_API_USER}."
    unset token
    ok "Stock Wazuh API credential authenticated successfully"
  else
    log "Stock beta5 API password is not exposed; standalone API authentication check skipped."
  fi

  wazuh_dashboard_login_ok "$WAZUH_ADMIN_USER" "$WAZUH_ADMIN_PASSWORD" || \
    die "Wazuh dashboard UI rejected the stock admin credential."
  ok "Stock Wazuh dashboard UI login authenticated successfully"
}

shuffle_http_ok() {
  case "${1:-}" in 200|201|202|204|301|302|401|403) return 0 ;; *) return 1 ;; esac
}

detect_shuffle_url() {
  local code
  code="$(curl -ksS -o /tmp/soclab-shuffle-https.out -w '%{http_code}' --max-time 10 \
    "https://localhost:${SHUFFLE_HTTPS_PORT}/" || true)"
  if shuffle_http_ok "$code"; then
    SHUFFLE_DETECTED_URL="https://localhost:${SHUFFLE_HTTPS_PORT}"
    return 0
  fi

  code="$(curl -sS -o /tmp/soclab-shuffle-http.out -w '%{http_code}' --max-time 10 \
    "http://localhost:${SHUFFLE_FRONTEND_PORT}/" || true)"
  if shuffle_http_ok "$code"; then
    SHUFFLE_DETECTED_URL="http://localhost:${SHUFFLE_FRONTEND_PORT}"
    return 0
  fi
  return 1
}

shuffle_login_against_base() {
  local base="$1" username="$2" password="$3"
  local payload response cookie code endpoint
  payload="$(json_login_payload "$username" "$password")"
  response="$(mktemp /tmp/soclab-shuffle-login-response.XXXXXX)"
  cookie="$(mktemp /tmp/soclab-shuffle-login-cookie.XXXXXX)"
  chmod 600 "$response" "$cookie"

  for endpoint in '/api/v1/users/login' '/api/v1/login'; do
    code="$(printf '%s' "$payload" | curl -ksS --max-time 15 \
      -c "$cookie" -o "$response" -w '%{http_code}' \
      -H 'Content-Type: application/json' --data-binary @- "${base}${endpoint}" || true)"
    if [[ "$code" == "200" ]] && ! grep -qiE '"success"[[:space:]]*:[[:space:]]*false|invalid credential|wrong password' "$response"; then
      SHUFFLE_API_BASE_URL="$base"
      SHUFFLE_LOGIN_COOKIE_FILE="$cookie"
      rm -f "$response"
      unset payload
      return 0
    fi
  done

  rm -f "$response" "$cookie"
  unset payload
  return 1
}

verify_shuffle_ui_credentials() {
  local base
  [[ -n "${SHUFFLE_ADMIN_USERNAME:-}" && -n "${SHUFFLE_ADMIN_PASSWORD:-}" ]] || return 2
  for base in "$SHUFFLE_DETECTED_URL" "http://localhost:${SHUFFLE_BACKEND_PORT}"; do
    [[ -n "$base" ]] || continue
    if shuffle_login_against_base "$base" "$SHUFFLE_ADMIN_USERNAME" "$SHUFFLE_ADMIN_PASSWORD"; then
      ok "Stock Shuffle UI credential authenticated successfully"
      return 0
    fi
  done
  return 1
}

compose_env_first() {
  local cfg="$1" key="$2"
  printf '%s' "$cfg" | jq -r --arg key "$key" \
    '[.services[]?.environment?[$key] // empty | select(type == "string" and length > 0)] | .[0] // empty'
}

capture_shuffle_stock_credentials() {
  local cfg initial_os
  log "Reading stock Shuffle values from the rendered Compose model (values are not logged)"
  cfg="$(cd "$SHUFFLE_DIR" && docker compose config --format json)" || \
    die "Could not render Shuffle Compose config as JSON."

  SHUFFLE_ADMIN_USERNAME="$(compose_env_first "$cfg" SHUFFLE_DEFAULT_USERNAME)"
  SHUFFLE_ADMIN_PASSWORD="$(compose_env_first "$cfg" SHUFFLE_DEFAULT_PASSWORD)"
  SHUFFLE_API_KEY="$(compose_env_first "$cfg" SHUFFLE_DEFAULT_APIKEY)"
  SHUFFLE_ENCRYPTION_MODIFIER="$(compose_env_first "$cfg" SHUFFLE_ENCRYPTION_MODIFIER)"
  SHUFFLE_OPENSEARCH_PASSWORD="$(compose_env_first "$cfg" SHUFFLE_OPENSEARCH_PASSWORD)"
  initial_os="$(compose_env_first "$cfg" OPENSEARCH_INITIAL_ADMIN_PASSWORD)"
  [[ -n "$SHUFFLE_OPENSEARCH_PASSWORD" ]] || SHUFFLE_OPENSEARCH_PASSWORD="$initial_os"
  unset cfg initial_os

  if [[ -n "$SHUFFLE_ADMIN_USERNAME" && -n "$SHUFFLE_ADMIN_PASSWORD" ]]; then
    ok "Stock Shuffle UI default account detected"
  else
    log "Shuffle upstream defines no default UI username/password; first-run registration remains unchanged."
  fi
  [[ -n "$SHUFFLE_OPENSEARCH_PASSWORD" ]] && ok "Stock Shuffle OpenSearch credential detected in memory"
}

# Use the upstream .env and Compose credential defaults unchanged. We only set
# local host-port values required to coexist with Wazuh on this workstation.
install_shuffle() {
  phase "PHASE 5/7 - INSTALL STOCK SHUFFLE"
  log "Cloning Shuffle"
  git clone --depth 1 https://github.com/Shuffle/Shuffle.git "$SHUFFLE_DIR"
  [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]] || die "Shuffle docker-compose.yml is missing."
  [[ -f "$SHUFFLE_DIR/.env" ]] || die "Shuffle upstream .env is missing."

  patch_shuffle_compose

  local env_file="$SHUFFLE_DIR/.env"
  upsert_env "$env_file" "FRONTEND_PORT" "$SHUFFLE_FRONTEND_PORT"
  upsert_env "$env_file" "FRONTEND_PORT_HTTPS" "$SHUFFLE_HTTPS_PORT"
  upsert_env "$env_file" "BACKEND_PORT" "$SHUFFLE_BACKEND_PORT"
  chmod 600 "$env_file"

  mkdir -p "$SHUFFLE_DIR/shuffle-database" "$SHUFFLE_DIR/shuffle-apps" "$SHUFFLE_DIR/shuffle-files"
  chown -R 1000:1000 "$SHUFFLE_DIR/shuffle-database" 2>/dev/null || true

  log "Validating stock Shuffle Compose configuration"
  (cd "$SHUFFLE_DIR" && docker compose config --quiet)
  capture_shuffle_stock_credentials

  log "Pulling Shuffle images"
  (cd "$SHUFFLE_DIR" && docker compose pull)
  log "Starting Shuffle with upstream/default credentials unchanged"
  if ! (cd "$SHUFFLE_DIR" && docker compose up -d --remove-orphans); then
    (cd "$SHUFFLE_DIR" && docker compose ps -a && docker compose logs --tail 250) || true
    die "Shuffle docker compose up failed."
  fi

  local start
  start="$(date +%s)"
  until detect_shuffle_url; do
    if (( $(date +%s) - start >= 480 )); then
      (cd "$SHUFFLE_DIR" && docker compose ps -a && docker compose logs --tail 300) || true
      die "Shuffle frontend failed its health gate."
    fi
    sleep 10
  done
  SHUFFLE_API_BASE_URL="$SHUFFLE_DETECTED_URL"
  ok "Shuffle frontend reachable at ${SHUFFLE_DETECTED_URL}"

  if [[ -n "$SHUFFLE_ADMIN_USERNAME" && -n "$SHUFFLE_ADMIN_PASSWORD" ]]; then
    verify_shuffle_ui_credentials || die "Shuffle rejected its own stock UI credential."
  else
    ok "Shuffle is running with upstream first-run registration; no UI password was invented or changed"
  fi
}

verify_live_user_credentials() {
  wazuh_dashboard_login_ok "$WAZUH_ADMIN_USER" "$WAZUH_ADMIN_PASSWORD" || \
    die "Final Wazuh stock UI authentication verification failed."

  if [[ -n "${SHUFFLE_ADMIN_USERNAME:-}" && -n "${SHUFFLE_ADMIN_PASSWORD:-}" ]]; then
    verify_shuffle_ui_credentials || die "Final Shuffle stock UI authentication verification failed."
  else
    log "Shuffle has no upstream default UI account; skipping UI credential test and preserving first-run registration."
  fi
  ok "Final default-credential verification completed"
}
