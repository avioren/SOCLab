#!/usr/bin/env bash
# shellcheck shell=bash

password_policy_ok() {
  local value="${1:-}"
  (( ${#value} >= 8 && ${#value} <= 64 )) || return 1
  [[ "$value" =~ [A-Z] ]] || return 1
  [[ "$value" =~ [a-z] ]] || return 1
  [[ "$value" =~ [0-9] ]] || return 1
  printf '%s' "$value" | grep -qE '[.*+?-]' || return 1
  printf '%s' "$value" | grep -qE '^[A-Za-z0-9.*+?-]+$' || return 1
}

read_password_masked() {
  local prompt="$1" outvar="$2" char value=""
  printf '%s' "$prompt" >/dev/tty

  while IFS= read -r -s -n 1 char </dev/tty; do
    if [[ -z "$char" ]]; then
      printf '\n' >/dev/tty
      break
    fi

    case "$char" in
      $'\177'|$'\b')
        if (( ${#value} > 0 )); then
          value="${value%?}"
          printf '\b \b' >/dev/tty
        fi
        ;;
      *)
        value+="$char"
        printf '*' >/dev/tty
        ;;
    esac
  done

  printf -v "$outvar" '%s' "$value"
  unset char value
}

prompt_password() {
  local label="$1" outvar="$2" first second
  while true; do
    read_password_masked "$label: " first
    if ! password_policy_ok "$first"; then
      printf 'Password must be 8-64 characters and contain uppercase, lowercase, number, and one of . * + ? -\n' >/dev/tty
      continue
    fi
    read_password_masked "Confirm $label: " second
    [[ "$first" == "$second" ]] || {
      printf 'Passwords do not match. Try again.\n' >/dev/tty
      continue
    }
    printf -v "$outvar" '%s' "$first"
    unset first second
    return 0
  done
}

generate_password() {
  local outvar="$1" value
  value="A1.$(openssl rand -hex 14)a"
  password_policy_ok "$value" || die "Internal password generation failed policy validation."
  printf -v "$outvar" '%s' "$value"
  unset value
}

prompt_browser_url() {
  local label="$1" default="$2" outvar="$3" value
  while true; do
    IFS= read -r -p "$label [$default]: " value </dev/tty
    [[ -n "$value" ]] || value="$default"
    if [[ "$value" =~ ^https?://[^[:space:]]+$ ]]; then
      printf -v "$outvar" '%s' "${value%/}"
      return 0
    fi
    printf 'Enter a full http:// or https:// URL.\n' >/dev/tty
  done
}

collect_runtime_credentials() {
  [[ -r /dev/tty ]] || die "Interactive terminal required to collect runtime credentials."
  phase "RUNTIME CREDENTIALS - LOCAL ONLY"
  log "Choose the two UI accounts you will actually use. Internal service secrets are generated locally."
  log "Password fields are masked with * characters. Username/email and URL fields remain visible."
  log "No password, token, API key, or encryption secret is written to Git or the installer log."

  prompt_password "Wazuh dashboard admin password (username: ${WAZUH_ADMIN_USER})" WAZUH_ADMIN_PASSWORD

  local entered_user
  IFS= read -r -p "Shuffle admin username/email [$SHUFFLE_ADMIN_USERNAME]: " entered_user </dev/tty
  [[ -n "$entered_user" ]] && SHUFFLE_ADMIN_USERNAME="$entered_user"
  [[ "$SHUFFLE_ADMIN_USERNAME" =~ ^[A-Za-z0-9._+@-]+$ ]] || die "Shuffle username contains unsupported characters."
  prompt_password "Shuffle UI admin password" SHUFFLE_ADMIN_PASSWORD

  generate_password WAZUH_DASHBOARD_SERVICE_PASSWORD
  generate_password WAZUH_API_PASSWORD
  generate_password SHUFFLE_OPENSEARCH_PASSWORD
  SHUFFLE_ENCRYPTION_MODIFIER="$(openssl rand -hex 32)"
  SHUFFLE_API_KEY=""

  ok "User-facing credentials collected; internal service credentials generated in memory"
}

collect_browser_urls() {
  [[ -r /dev/tty ]] || die "Interactive terminal required to confirm browser URLs."
  local detected_wazuh="https://localhost:${WAZUH_DASHBOARD_PORT}"
  local detected_shuffle="${SHUFFLE_DETECTED_URL:-http://localhost:${SHUFFLE_FRONTEND_PORT}}"

  phase "CONFIRM BROWSER URLS"
  log "These are the URLs that will be written to the local credential inventory."
  log "Accept localhost defaults when you will browse from this Windows/WSL workstation; otherwise enter the hostname/IP you use in your browser."
  prompt_browser_url "Wazuh dashboard URL" "$detected_wazuh" WAZUH_DASHBOARD_BROWSER_URL
  prompt_browser_url "Shuffle URL" "$detected_shuffle" SHUFFLE_BROWSER_URL
}

write_credentials_file() {
  [[ -n "${WAZUH_DASHBOARD_BROWSER_URL:-}" ]] || die "Wazuh browser URL has not been confirmed."
  [[ -n "${SHUFFLE_BROWSER_URL:-}" ]] || die "Shuffle browser URL has not been confirmed."

  mkdir -p "$STATE_DIR"
  local tmp owner group
  tmp="$(mktemp "$STATE_DIR/.credentials.XXXXXX")"
  chmod 600 "$tmp"
  cat >"$tmp" <<EOF
# SOC Lab VERIFIED runtime credentials - LOCAL FILE, NEVER COMMIT TO GIT
# Written only after service and authentication verification on $(date -Is)
WAZUH_VERSION=${WAZUH_VERSION}
WAZUH_DASHBOARD_URL=${WAZUH_DASHBOARD_BROWSER_URL}
WAZUH_DASHBOARD_USERNAME=${WAZUH_ADMIN_USER}
WAZUH_DASHBOARD_PASSWORD=${WAZUH_ADMIN_PASSWORD}
WAZUH_INDEXER_URL=https://localhost:9200
WAZUH_INDEXER_USERNAME=${WAZUH_ADMIN_USER}
WAZUH_INDEXER_PASSWORD=${WAZUH_ADMIN_PASSWORD}
WAZUH_DASHBOARD_SERVICE_USERNAME=${WAZUH_DASHBOARD_SERVICE_USER}
WAZUH_DASHBOARD_SERVICE_PASSWORD=${WAZUH_DASHBOARD_SERVICE_PASSWORD}
WAZUH_API_URL=https://localhost:55000
WAZUH_API_USERNAME=${WAZUH_API_USER}
WAZUH_API_PASSWORD=${WAZUH_API_PASSWORD}
SHUFFLE_URL=${SHUFFLE_BROWSER_URL}
SHUFFLE_UI_USERNAME=${SHUFFLE_ADMIN_USERNAME}
SHUFFLE_UI_PASSWORD=${SHUFFLE_ADMIN_PASSWORD}
SHUFFLE_API_URL=${SHUFFLE_API_BASE_URL:-${SHUFFLE_DETECTED_URL}}/api/v1
SHUFFLE_OPENSEARCH_URL=https://localhost:${SHUFFLE_OPENSEARCH_PORT}
SHUFFLE_OPENSEARCH_USERNAME=admin
SHUFFLE_OPENSEARCH_PASSWORD=${SHUFFLE_OPENSEARCH_PASSWORD}
SHUFFLE_ENCRYPTION_MODIFIER=${SHUFFLE_ENCRYPTION_MODIFIER}
EOF
  if [[ -n "${SHUFFLE_API_KEY:-}" ]]; then
    printf 'SHUFFLE_API_KEY=%s\n' "$SHUFFLE_API_KEY" >>"$tmp"
  else
    printf 'SHUFFLE_API_KEY_STATUS=not_generated_use_Shuffle_Settings_to_generate_one\n' >>"$tmp"
  fi

  mv -f "$tmp" "$STATE_DIR/credentials.txt"
  chmod 600 "$STATE_DIR/credentials.txt"
  owner="${SUDO_USER:-root}"
  if id "$owner" >/dev/null 2>&1; then
    group="$(id -gn "$owner")"
    chown "$owner:$group" "$STATE_DIR/credentials.txt"
  fi
  ok "Verified local credential inventory written to $STATE_DIR/credentials.txt (mode 600)"
}

credential_value() {
  local key="$1" file="$STATE_DIR/credentials.txt"
  [[ -r "$file" ]] || return 1
  awk -v key="$key" 'index($0, key "=") == 1 {sub(/^[^=]*=/, ""); print; exit}' "$file"
}
