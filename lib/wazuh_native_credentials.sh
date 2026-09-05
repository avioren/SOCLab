#!/usr/bin/env bash
# shellcheck shell=bash

# Replace only installer-owned certificate directories. Do not touch Wazuh
# security-user files or password databases.
generate_wazuh_certs_locally() {
  phase "PHASE 3/7 - GENERATE FRESH WAZUH 5 TLS CERTIFICATES"
  [[ -n "$WAZUH_INDEXER_UID" && -n "$WAZUH_MANAGER_UID" && -n "$WAZUH_DASHBOARD_UID" ]] || \
    die "Service UID/GID values were not detected before certificate generation."

  local ca_dir="$WAZUH_SINGLE/config/root-ca"
  local idx_dir="$WAZUH_SINGLE/config/wazuh_indexer"
  local mgr_dir="$WAZUH_SINGLE/config/wazuh_manager"
  local dash_dir="$WAZUH_SINGLE/config/wazuh_dashboard"

  rm -rf "$ca_dir"
  rm -rf "$idx_dir/certs" "$idx_dir/private" \
         "$mgr_dir/certs" "$mgr_dir/private" \
         "$dash_dir/certs" "$dash_dir/private"
  mkdir -p "$ca_dir/certs" "$ca_dir/private" \
           "$idx_dir/certs" "$idx_dir/private" \
           "$mgr_dir/certs" "$mgr_dir/private" \
           "$dash_dir/certs" "$dash_dir/private"

  chmod 755 "$ca_dir" "$ca_dir/certs" \
            "$idx_dir" "$idx_dir/certs" \
            "$mgr_dir" "$mgr_dir/certs" \
            "$dash_dir" "$dash_dir/certs"
  chmod 700 "$ca_dir/private" "$idx_dir/private" \
            "$mgr_dir/private" "$dash_dir/private"

  local ca_key="$ca_dir/private/root-ca-key.pem"
  local ca_cert="$ca_dir/certs/root-ca.pem"
  log "Generating root CA"
  openssl genrsa -out "$ca_key" 2048 >/dev/null 2>&1
  openssl req -x509 -new -nodes -key "$ca_key" -sha256 -days 3650 \
    -out "$ca_cert" \
    -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=Wazuh Root CA" \
    >/dev/null 2>&1

  make_cert() {
    local filename="$1" dir="$2" cn="$3" san="$4"
    local key="$2/certs/$1-key.pem" cert="$2/certs/$1.pem"
    local csr="$2/private/$1.csr" ext="$2/private/$1.ext"
    log "Generating certificate: $filename"
    openssl genrsa -out "$key" 2048 >/dev/null 2>&1
    openssl req -new -key "$key" -out "$csr" \
      -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=${cn}" >/dev/null 2>&1
    cat >"$ext" <<EOF
subjectAltName=${san}
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
EOF
    openssl x509 -req -in "$csr" -CA "$ca_cert" -CAkey "$ca_key" \
      -CAcreateserial -out "$cert" -days 3650 -sha256 -extfile "$ext" \
      >/dev/null 2>&1
    cp -f "$key" "$dir/private/${filename}-key.pem"
  }

  make_cert "wazuh.indexer" "$idx_dir" "wazuh.indexer" "DNS:wazuh.indexer,DNS:localhost,IP:127.0.0.1"
  make_cert "admin" "$idx_dir" "admin" "DNS:admin,DNS:localhost,IP:127.0.0.1"
  make_cert "wazuh.manager" "$mgr_dir" "wazuh.manager" "DNS:wazuh.manager,DNS:localhost,IP:127.0.0.1"
  make_cert "wazuh.dashboard" "$dash_dir" "wazuh.dashboard" "DNS:wazuh.dashboard,DNS:localhost,IP:127.0.0.1"

  chown root:root "$ca_cert" \
    "$idx_dir/certs/wazuh.indexer.pem" "$idx_dir/certs/admin.pem" \
    "$mgr_dir/certs/wazuh.manager.pem" "$dash_dir/certs/wazuh.dashboard.pem"
  chmod 644 "$ca_cert" \
    "$idx_dir/certs/wazuh.indexer.pem" "$idx_dir/certs/admin.pem" \
    "$mgr_dir/certs/wazuh.manager.pem" "$dash_dir/certs/wazuh.dashboard.pem"

  chown "${WAZUH_INDEXER_UID}:${WAZUH_INDEXER_GID}" \
    "$idx_dir/certs/wazuh.indexer-key.pem" "$idx_dir/certs/admin-key.pem"
  chmod 640 "$idx_dir/certs/wazuh.indexer-key.pem" "$idx_dir/certs/admin-key.pem"
  chown "${WAZUH_MANAGER_UID}:${WAZUH_MANAGER_GID}" "$mgr_dir/certs/wazuh.manager-key.pem"
  chmod 640 "$mgr_dir/certs/wazuh.manager-key.pem"
  chown "${WAZUH_DASHBOARD_UID}:${WAZUH_DASHBOARD_GID}" "$dash_dir/certs/wazuh.dashboard-key.pem"
  chmod 640 "$dash_dir/certs/wazuh.dashboard-key.pem"
  chmod 600 "$ca_key" "$idx_dir/private/"*.pem "$mgr_dir/private/"*.pem "$dash_dir/private/"*.pem 2>/dev/null || true

  local required=(
    "$ca_dir/certs/root-ca.pem"
    "$idx_dir/certs/wazuh.indexer.pem"
    "$idx_dir/certs/wazuh.indexer-key.pem"
    "$idx_dir/certs/admin.pem"
    "$idx_dir/certs/admin-key.pem"
    "$mgr_dir/certs/wazuh.manager.pem"
    "$mgr_dir/certs/wazuh.manager-key.pem"
    "$dash_dir/certs/wazuh.dashboard.pem"
    "$dash_dir/certs/wazuh.dashboard-key.pem"
  ) f
  for f in "${required[@]}"; do
    [[ -s "$f" ]] || die "Missing generated certificate: $f"
  done

  local idx_dn admin_dn
  idx_dn="$(openssl x509 -in "$idx_dir/certs/wazuh.indexer.pem" -noout -subject -nameopt RFC2253 | sed 's/^subject=//' | tr -d ' ')"
  admin_dn="$(openssl x509 -in "$idx_dir/certs/admin.pem" -noout -subject -nameopt RFC2253 | sed 's/^subject=//' | tr -d ' ')"
  [[ "$idx_dn" == "CN=wazuh.indexer,OU=Wazuh,O=Wazuh,L=California,C=US" ]] || die "Unexpected indexer certificate DN: $idx_dn"
  [[ "$admin_dn" == "CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US" ]] || die "Unexpected admin certificate DN: $admin_dn"
  ok "Fresh Wazuh TLS certificates generated without modifying credentials"
}

# Read exactly what the pinned upstream Compose model will use. Nothing is
# changed or written back to the Wazuh source tree.
capture_wazuh_stock_credentials() {
  local cfg
  log "Reading stock beta5 credentials from the rendered Compose model (values are not logged)"
  cfg="$(cd "$WAZUH_SINGLE" && docker compose config --format json)" || \
    die "Could not render Wazuh Compose config as JSON."

  WAZUH_ADMIN_USER="$(printf '%s' "$cfg" | jq -r '.services["wazuh.manager"].environment.INDEXER_USERNAME // "admin"')"
  WAZUH_ADMIN_PASSWORD="$(printf '%s' "$cfg" | jq -r '.services["wazuh.manager"].environment.INDEXER_PASSWORD // empty')"
  WAZUH_DASHBOARD_SERVICE_USER="$(printf '%s' "$cfg" | jq -r '.services["wazuh.dashboard"].environment.DASHBOARD_USERNAME // "kibanaserver"')"
  WAZUH_DASHBOARD_SERVICE_PASSWORD="$(printf '%s' "$cfg" | jq -r '.services["wazuh.dashboard"].environment.DASHBOARD_PASSWORD // empty')"
  WAZUH_API_USER="$(printf '%s' "$cfg" | jq -r '.services["wazuh.manager"].environment.API_USERNAME // .services["wazuh.dashboard"].environment.API_USERNAME // "wazuh-wui"')"
  WAZUH_API_PASSWORD="$(printf '%s' "$cfg" | jq -r '.services["wazuh.manager"].environment.API_PASSWORD // .services["wazuh.dashboard"].environment.API_PASSWORD // empty')"
  unset cfg

  [[ -n "$WAZUH_ADMIN_PASSWORD" ]] || die "Could not discover stock beta5 INDEXER_PASSWORD."
  [[ -n "$WAZUH_DASHBOARD_SERVICE_PASSWORD" ]] || die "Could not discover stock beta5 DASHBOARD_PASSWORD."
  [[ -n "$WAZUH_API_PASSWORD" ]] || die "Could not discover stock beta5 API_PASSWORD."
  ok "Stock Wazuh credentials captured in memory without modification"
}
