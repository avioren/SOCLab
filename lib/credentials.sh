#!/usr/bin/env bash
# shellcheck shell=bash

# The lab intentionally keeps upstream/default credentials unchanged. This
# function exists to preserve the installer flow while making it explicitly
# non-interactive.
collect_runtime_credentials() {
  phase "RUNTIME CREDENTIALS - STOCK DEFAULTS"
  log "No password or username prompts will be shown."
  log "Wazuh and Shuffle credentials will be read from their rendered upstream Compose defaults after cloning."
  log "No password will be changed, generated, or rotated by this installer."
  ok "Installer configured to preserve stock/default credentials"
}

# Browser URLs are deterministic for this WSL2/Docker Desktop lab. Do not stop
# the install for interactive URL confirmation.
collect_browser_urls() {
  WAZUH_DASHBOARD_BROWSER_URL="https://localhost:${WAZUH_DASHBOARD_PORT}"
  SHUFFLE_BROWSER_URL="${SHUFFLE_DETECTED_URL:-http://localhost:${SHUFFLE_FRONTEND_PORT}}"
  ok "Browser URLs selected automatically: Wazuh=${WAZUH_DASHBOARD_BROWSER_URL}, Shuffle=${SHUFFLE_BROWSER_URL}"
}

write_credentials_file() {
  [[ -n "${WAZUH_DASHBOARD_BROWSER_URL:-}" ]] || die "Wazuh browser URL was not determined."
  [[ -n "${SHUFFLE_BROWSER_URL:-}" ]] || die "Shuffle browser URL was not determined."

  mkdir -p "$STATE_DIR"
  local tmp owner group
  tmp="$(mktemp "$STATE_DIR/.credentials.XXXXXX")"
  chmod 600 "$tmp"
  cat >"$tmp" <<EOF
# SOC Lab runtime credentials - LOCAL FILE, NEVER COMMIT TO GIT
# Values below are stock/default credentials discovered from upstream runtime
# configuration. The installer does not change passwords.
# Written after service verification on $(date -Is)
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
SHUFFLE_URL=${SHUFFLE_BROWSER_URL}
SHUFFLE_API_URL=${SHUFFLE_API_BASE_URL:-${SHUFFLE_DETECTED_URL}}/api/v1
SHUFFLE_OPENSEARCH_URL=https://localhost:${SHUFFLE_OPENSEARCH_PORT}
SHUFFLE_OPENSEARCH_USERNAME=admin
EOF

  if [[ -n "${WAZUH_API_PASSWORD:-}" ]]; then
    printf 'WAZUH_API_PASSWORD=%s\n' "$WAZUH_API_PASSWORD" >>"$tmp"
  else
    printf 'WAZUH_API_CREDENTIAL_STATUS=stock_api_password_not_exposed_by_pinned_beta5\n' >>"$tmp"
  fi

  if [[ -n "${SHUFFLE_ADMIN_USERNAME:-}" && -n "${SHUFFLE_ADMIN_PASSWORD:-}" ]]; then
    printf 'SHUFFLE_UI_USERNAME=%s\n' "$SHUFFLE_ADMIN_USERNAME" >>"$tmp"
    printf 'SHUFFLE_UI_PASSWORD=%s\n' "$SHUFFLE_ADMIN_PASSWORD" >>"$tmp"
  else
    printf 'SHUFFLE_UI_CREDENTIAL_STATUS=no_stock_default_ui_account_detected_use_upstream_first_run_registration\n' >>"$tmp"
  fi

  if [[ -n "${SHUFFLE_OPENSEARCH_PASSWORD:-}" ]]; then
    printf 'SHUFFLE_OPENSEARCH_PASSWORD=%s\n' "$SHUFFLE_OPENSEARCH_PASSWORD" >>"$tmp"
  else
    printf 'SHUFFLE_OPENSEARCH_PASSWORD_STATUS=no_stock_value_detected\n' >>"$tmp"
  fi

  if [[ -n "${SHUFFLE_ENCRYPTION_MODIFIER:-}" ]]; then
    printf 'SHUFFLE_ENCRYPTION_MODIFIER=%s\n' "$SHUFFLE_ENCRYPTION_MODIFIER" >>"$tmp"
  fi

  if [[ -n "${SHUFFLE_API_KEY:-}" ]]; then
    printf 'SHUFFLE_API_KEY=%s\n' "$SHUFFLE_API_KEY" >>"$tmp"
  else
    printf 'SHUFFLE_API_KEY_STATUS=no_stock_api_key_detected\n' >>"$tmp"
  fi

  mv -f "$tmp" "$STATE_DIR/credentials.txt"
  chmod 600 "$STATE_DIR/credentials.txt"
  owner="${SUDO_USER:-root}"
  if id "$owner" >/dev/null 2>&1; then
    group="$(id -gn "$owner")"
    chown "$owner:$group" "$STATE_DIR/credentials.txt"
  fi
  ok "Stock/default credential inventory written to $STATE_DIR/credentials.txt (mode 600)"
}

credential_value() {
  local key="$1" file="$STATE_DIR/credentials.txt"
  [[ -r "$file" ]] || return 1
  awk -v key="$key" 'index($0, key "=") == 1 {sub(/^[^=]*=/, ""); print; exit}' "$file"
}
