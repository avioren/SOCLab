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

prompt_password() {
  local label="$1" outvar="$2" first second
  while true; do
    IFS= read -r -s -p "$label: " first </dev/tty
    printf '\n' >/dev/tty
    if ! password_policy_ok "$first"; then
      printf 'Password must be 8-64 characters and contain uppercase, lowercase, number, and one of . * + ? -\n' >/dev/tty
      continue
    fi
    IFS= read -r -s -p "Confirm $label: " second </dev/tty
    printf '\n' >/dev/tty
    [[ "$first" == "$second" ]] || {
      printf 'Passwords do not match. Try again.\n' >/dev/tty
      continue
    }
    printf -v "$outvar" '%s' "$first"
    unset first second
    return 0
  done
}

prompt_optional_secret() {
  local label="$1" outvar="$2" generated_bytes="${3:-32}" value
  while true; do
    IFS= read -r -s -p "$label (Enter = generate securely): " value </dev/tty
    printf '\n' >/dev/tty
    if [[ -z "$value" ]]; then
      value="$(openssl rand -hex "$generated_bytes")"
      printf -v "$outvar" '%s' "$value"
      unset value
      return 0
    fi
    if (( ${#value} < 32 )) || ! printf '%s' "$value" | grep -qE '^[A-Za-z0-9._-]+$'; then
      printf 'Use at least 32 characters from A-Z, a-z, 0-9, dot, underscore, or hyphen; or press Enter to generate.\n' >/dev/tty
      continue
    fi
    printf -v "$outvar" '%s' "$value"
    unset value
    return 0
  done
}

collect_runtime_credentials() {
  [[ -r /dev/tty ]] || die "Interactive terminal required to collect runtime credentials."
  phase "RUNTIME CREDENTIALS - LOCAL ONLY"
  log "Credentials are entered without echo and stored only under $STATE_DIR after cleanup."
  log "No password, token, API key, or encryption secret is written to Git or the installer log."

  prompt_password "Wazuh UI / Indexer admin password" WAZUH_ADMIN_PASSWORD
  prompt_password "Wazuh dashboard service (kibanaserver) password" WAZUH_DASHBOARD_SERVICE_PASSWORD
  prompt_password "Wazuh API wazuh-wui password" WAZUH_API_PASSWORD

  local entered_user
  IFS= read -r -p "Shuffle admin username/email [$SHUFFLE_ADMIN_USERNAME]: " entered_user </dev/tty
  [[ -n "$entered_user" ]] && SHUFFLE_ADMIN_USERNAME="$entered_user"
  [[ "$SHUFFLE_ADMIN_USERNAME" =~ ^[A-Za-z0-9._+@-]+$ ]] || die "Shuffle username contains unsupported characters."

  prompt_password "Shuffle UI admin password" SHUFFLE_ADMIN_PASSWORD
  prompt_password "Shuffle OpenSearch admin password" SHUFFLE_OPENSEARCH_PASSWORD
  prompt_optional_secret "Shuffle API key" SHUFFLE_API_KEY 32
  prompt_optional_secret "Shuffle encryption modifier" SHUFFLE_ENCRYPTION_MODIFIER 32
  ok "Runtime credentials collected in memory"
}

write_credentials_file() {
  mkdir -p "$STATE_DIR"
  local tmp owner group
  tmp="$(mktemp "$STATE_DIR/.credentials.XXXXXX")"
  chmod 600 "$tmp"
  cat >"$tmp" <<EOF
# SOC Lab runtime credentials - LOCAL FILE, NEVER COMMIT TO GIT
# Recorded by install.sh on $(date -Is)
WAZUH_VERSION=${WAZUH_VERSION}
WAZUH_DASHBOARD_URL=https://localhost:${WAZUH_DASHBOARD_PORT}
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
SHUFFLE_URL=http://localhost:${SHUFFLE_FRONTEND_PORT}
SHUFFLE_DEFAULT_USERNAME=${SHUFFLE_ADMIN_USERNAME}
SHUFFLE_DEFAULT_PASSWORD=${SHUFFLE_ADMIN_PASSWORD}
SHUFFLE_OPENSEARCH_URL=https://localhost:${SHUFFLE_OPENSEARCH_PORT}
SHUFFLE_OPENSEARCH_USERNAME=admin
SHUFFLE_OPENSEARCH_PASSWORD=${SHUFFLE_OPENSEARCH_PASSWORD}
SHUFFLE_DEFAULT_APIKEY=${SHUFFLE_API_KEY}
SHUFFLE_ENCRYPTION_MODIFIER=${SHUFFLE_ENCRYPTION_MODIFIER}
EOF
  mv -f "$tmp" "$STATE_DIR/credentials.txt"
  chmod 600 "$STATE_DIR/credentials.txt"
  owner="${SUDO_USER:-root}"
  if id "$owner" >/dev/null 2>&1; then
    group="$(id -gn "$owner")"
    chown "$owner:$group" "$STATE_DIR/credentials.txt"
  fi
  ok "Local credential inventory written to $STATE_DIR/credentials.txt (mode 600)"
}

credential_value() {
  local key="$1" file="$STATE_DIR/credentials.txt"
  [[ -r "$file" ]] || return 1
  awk -v key="$key" 'index($0, key "=") == 1 {sub(/^[^=]*=/, ""); print; exit}' "$file"
}
