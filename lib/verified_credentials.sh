#!/usr/bin/env bash
# shellcheck shell=bash
# Authentication/bootstrap overrides. Sourced after the base Wazuh/Shuffle modules.

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

# Override the base verifier: dashboard login must work, not just direct indexer auth.
verify_runtime_credentials() {
  local code token
  code="$(curl -ksS -o /tmp/soclab-admin-auth.out -w '%{http_code}' --max-time 10 \
    -u "${WAZUH_ADMIN_USER}:${WAZUH_ADMIN_PASSWORD}" https://localhost:9200/ || true)"
  [[ "$code" == "200" ]] || die "Wazuh admin/indexer credential verification failed (HTTP ${code:-none})."
  ok "Wazuh admin/indexer credential authenticated successfully"

  token="$(curl -ksS --max-time 15 -u "${WAZUH_API_USER}:${WAZUH_API_PASSWORD}" \
    -X POST 'https://localhost:55000/security/user/authenticate?raw=true' || true)"
  [[ -n "$token" && "$token" != *'error'* && "$token" != *'Unauthorized'* ]] || \
    die "Wazuh API credential verification failed for ${WAZUH_API_USER}."
  unset token
  ok "Wazuh API credential authenticated successfully"

  wazuh_dashboard_login_ok "$WAZUH_ADMIN_USER" "$WAZUH_ADMIN_PASSWORD" || \
    die "Wazuh dashboard UI rejected the admin credential. The installer will not write it to credentials.txt."
  ok "Wazuh dashboard UI login authenticated successfully"
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
  for base in "$SHUFFLE_DETECTED_URL" "http://localhost:${SHUFFLE_BACKEND_PORT}"; do
    [[ -n "$base" ]] || continue
    if shuffle_login_against_base "$base" "$SHUFFLE_ADMIN_USERNAME" "$SHUFFLE_ADMIN_PASSWORD"; then
      ok "Shuffle UI/admin credential authenticated successfully"
      return 0
    fi
  done
  return 1
}

register_shuffle_admin_against_base() {
  local base="$1" payload response code endpoint
  payload="$(json_login_payload "$SHUFFLE_ADMIN_USERNAME" "$SHUFFLE_ADMIN_PASSWORD")"
  response="$(mktemp /tmp/soclab-shuffle-register-response.XXXXXX)"
  chmod 600 "$response"

  for endpoint in '/api/v1/users/register' '/api/v1/register'; do
    code="$(printf '%s' "$payload" | curl -ksS --max-time 20 \
      -o "$response" -w '%{http_code}' -H 'Content-Type: application/json' \
      --data-binary @- "${base}${endpoint}" || true)"
    if [[ "$code" == "200" || "$code" == "201" ]]; then
      if ! grep -qiE '"success"[[:space:]]*:[[:space:]]*false|failed|error' "$response"; then
        rm -f "$response"
        unset payload
        return 0
      fi
    fi
  done

  rm -f "$response"
  unset payload
  return 1
}

bootstrap_shuffle_admin() {
  phase "CREATE AND VERIFY SHUFFLE ADMIN"
  local base

  # A clean install should have no users. We intentionally do not rely on
  # SHUFFLE_DEFAULT_USERNAME/PASSWORD bootstrap behavior.
  for base in "$SHUFFLE_DETECTED_URL" "http://localhost:${SHUFFLE_BACKEND_PORT}"; do
    [[ -n "$base" ]] || continue
    if register_shuffle_admin_against_base "$base"; then
      ok "Shuffle first admin account created from the username/password you supplied"
      break
    fi
  done

  # If registration reported an existing user, a successful login is also
  # acceptable. In either case the credential must really authenticate.
  verify_shuffle_ui_credentials || \
    die "Shuffle rejected the admin username/password you supplied. Nothing will be written to credentials.txt."

  # Best effort: create/read the current user's API key using the authenticated
  # session. Failure here does not make the UI credential invalid.
  if [[ -n "${SHUFFLE_LOGIN_COOKIE_FILE:-}" && -f "$SHUFFLE_LOGIN_COOKIE_FILE" ]]; then
    local response code apikey
    response="$(mktemp /tmp/soclab-shuffle-apikey-response.XXXXXX)"
    chmod 600 "$response"
    code="$(curl -ksS --max-time 15 -b "$SHUFFLE_LOGIN_COOKIE_FILE" \
      -o "$response" -w '%{http_code}' "${SHUFFLE_API_BASE_URL}/api/v1/users/generateapikey" || true)"
    if [[ "$code" == "200" ]]; then
      apikey="$(jq -r '.apikey // empty' "$response" 2>/dev/null || true)"
      [[ -n "$apikey" && "$apikey" != "null" ]] && SHUFFLE_API_KEY="$apikey"
      unset apikey
    fi
    rm -f "$response" "$SHUFFLE_LOGIN_COOKIE_FILE"
    SHUFFLE_LOGIN_COOKIE_FILE=""
  fi
}

# Override the base Shuffle installer. Core Docker behavior stays the same;
# only user bootstrap/authentication differs.
install_shuffle() {
  phase "PHASE 5/7 - INSTALL SHUFFLE"
  log "Cloning Shuffle"
  git clone --depth 1 https://github.com/Shuffle/Shuffle.git "$SHUFFLE_DIR"
  [[ -f "$SHUFFLE_DIR/docker-compose.yml" ]] || die "Shuffle docker-compose.yml is missing."
  patch_shuffle_compose

  local env_file="$SHUFFLE_DIR/.env"
  touch "$env_file"
  chmod 600 "$env_file"

  upsert_env "$env_file" "ENVIRONMENT_NAME" "Shuffle"
  upsert_env "$env_file" "FRONTEND_PORT" "$SHUFFLE_FRONTEND_PORT"
  upsert_env "$env_file" "FRONTEND_PORT_HTTPS" "$SHUFFLE_HTTPS_PORT"
  upsert_env "$env_file" "BACKEND_PORT" "$SHUFFLE_BACKEND_PORT"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_PORT" "$SHUFFLE_OPENSEARCH_PORT"
  upsert_env "$env_file" "OPENSEARCH_INITIAL_ADMIN_PASSWORD" "$SHUFFLE_OPENSEARCH_PASSWORD"
  upsert_env "$env_file" "SHUFFLE_OPENSEARCH_PASSWORD" "$SHUFFLE_OPENSEARCH_PASSWORD"

  # Explicitly disable guessed/default UI bootstrap credentials. The first UI
  # account is created through Shuffle's registration API and then logged in.
  upsert_env "$env_file" "SHUFFLE_DEFAULT_USERNAME" ""
  upsert_env "$env_file" "SHUFFLE_DEFAULT_PASSWORD" ""
  upsert_env "$env_file" "SHUFFLE_DEFAULT_APIKEY" ""

  upsert_env "$env_file" "SHUFFLE_ENCRYPTION_MODIFIER" "$SHUFFLE_ENCRYPTION_MODIFIER"
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
  until detect_shuffle_url; do
    if (( $(date +%s) - start >= 480 )); then
      (cd "$SHUFFLE_DIR" && docker compose ps -a && docker compose logs --tail 300) || true
      die "Shuffle frontend failed its health gate."
    fi
    sleep 10
  done
  ok "Shuffle frontend reachable at ${SHUFFLE_DETECTED_URL}"

  bootstrap_shuffle_admin
  ok "Shuffle passed frontend and authenticated-admin verification"
}

verify_live_user_credentials() {
  wazuh_dashboard_login_ok "$WAZUH_ADMIN_USER" "$WAZUH_ADMIN_PASSWORD" || \
    die "Final Wazuh UI authentication verification failed."
  verify_shuffle_ui_credentials || \
    die "Final Shuffle UI authentication verification failed."
  ok "Both user-facing UI credentials are verified"
}
