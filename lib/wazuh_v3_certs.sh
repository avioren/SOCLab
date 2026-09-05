#!/usr/bin/env bash
# shellcheck shell=bash
# Exact certificate-generation behavior from the last known-working v3 installer.

generate_wazuh_certs_locally() {
  phase "PHASE 3/7 - GENERATE FRESH WAZUH 5 TLS CERTIFICATES"

  [[ -n "$WAZUH_INDEXER_UID" && -n "$WAZUH_MANAGER_UID" && -n "$WAZUH_DASHBOARD_UID" ]] || \
    die "Service UID/GID values were not detected before certificate generation."

  local cfg="$WAZUH_SINGLE/config"
  local ca_dir="$cfg/root-ca"
  local idx_dir="$cfg/wazuh_indexer"
  local mgr_dir="$cfg/wazuh_manager"
  local dash_dir="$cfg/wazuh_dashboard"

  rm -rf "$ca_dir" "$idx_dir" "$mgr_dir" "$dash_dir"

  mkdir -p \
    "$ca_dir/certs" "$ca_dir/private" \
    "$idx_dir/certs" "$idx_dir/private" \
    "$mgr_dir/certs" "$mgr_dir/private" \
    "$dash_dir/certs" "$dash_dir/private"

  chmod 755 \
    "$ca_dir" "$ca_dir/certs" \
    "$idx_dir" "$idx_dir/certs" \
    "$mgr_dir" "$mgr_dir/certs" \
    "$dash_dir" "$dash_dir/certs"

  chmod 700 \
    "$ca_dir/private" \
    "$idx_dir/private" \
    "$mgr_dir/private" \
    "$dash_dir/private"

  local ca_key="$ca_dir/private/root-ca-key.pem"
  local ca_cert="$ca_dir/certs/root-ca.pem"

  log "Generating root CA"
  openssl genrsa -out "$ca_key" 2048 >/dev/null 2>&1
  openssl req -x509 -new -nodes \
    -key "$ca_key" \
    -sha256 -days 3650 \
    -out "$ca_cert" \
    -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=Wazuh Root CA" \
    >/dev/null 2>&1

  make_cert() {
    local filename="$1" dir="$2" cn="$3" san="$4"
    local key="$dir/certs/${filename}-key.pem"
    local cert="$dir/certs/${filename}.pem"
    local csr="$dir/private/${filename}.csr"
    local ext="$dir/private/${filename}.ext"

    log "Generating certificate: $filename"

    openssl genrsa -out "$key" 2048 >/dev/null 2>&1
    openssl req -new \
      -key "$key" \
      -out "$csr" \
      -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=${cn}" \
      >/dev/null 2>&1

    cat >"$ext" <<EOF
subjectAltName=${san}
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
EOF

    openssl x509 -req \
      -in "$csr" \
      -CA "$ca_cert" \
      -CAkey "$ca_key" \
      -CAcreateserial \
      -out "$cert" \
      -days 3650 -sha256 \
      -extfile "$ext" \
      >/dev/null 2>&1

    cp -f "$key" "$dir/private/${filename}-key.pem"
  }

  make_cert "wazuh.indexer" \
    "$idx_dir" "wazuh.indexer" \
    "DNS:wazuh.indexer,DNS:localhost,IP:127.0.0.1"

  make_cert "admin" \
    "$idx_dir" "admin" \
    "DNS:admin,DNS:localhost,IP:127.0.0.1"

  make_cert "wazuh.manager" \
    "$mgr_dir" "wazuh.manager" \
    "DNS:wazuh.manager,DNS:localhost,IP:127.0.0.1"

  make_cert "wazuh.dashboard" \
    "$dash_dir" "wazuh.dashboard" \
    "DNS:wazuh.dashboard,DNS:localhost,IP:127.0.0.1"

  chown root:root \
    "$ca_cert" \
    "$idx_dir/certs/wazuh.indexer.pem" \
    "$idx_dir/certs/admin.pem" \
    "$mgr_dir/certs/wazuh.manager.pem" \
    "$dash_dir/certs/wazuh.dashboard.pem"

  chmod 644 \
    "$ca_cert" \
    "$idx_dir/certs/wazuh.indexer.pem" \
    "$idx_dir/certs/admin.pem" \
    "$mgr_dir/certs/wazuh.manager.pem" \
    "$dash_dir/certs/wazuh.dashboard.pem"

  chown "${WAZUH_INDEXER_UID}:${WAZUH_INDEXER_GID}" \
    "$idx_dir/certs/wazuh.indexer-key.pem" \
    "$idx_dir/certs/admin-key.pem"
  chmod 640 \
    "$idx_dir/certs/wazuh.indexer-key.pem" \
    "$idx_dir/certs/admin-key.pem"

  chown "${WAZUH_MANAGER_UID}:${WAZUH_MANAGER_GID}" \
    "$mgr_dir/certs/wazuh.manager-key.pem"
  chmod 640 "$mgr_dir/certs/wazuh.manager-key.pem"

  chown "${WAZUH_DASHBOARD_UID}:${WAZUH_DASHBOARD_GID}" \
    "$dash_dir/certs/wazuh.dashboard-key.pem"
  chmod 640 "$dash_dir/certs/wazuh.dashboard-key.pem"

  chmod 600 "$ca_key" \
    "$idx_dir/private/"*.pem \
    "$mgr_dir/private/"*.pem \
    "$dash_dir/private/"*.pem \
    2>/dev/null || true

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
  )

  local f
  for f in "${required[@]}"; do
    [[ -s "$f" ]] || die "Missing generated certificate: $f"
  done

  local idx_dn admin_dn
  idx_dn="$(openssl x509 -in "$idx_dir/certs/wazuh.indexer.pem" -noout -subject -nameopt RFC2253 \
    | sed 's/^subject=//' | tr -d ' ')"
  admin_dn="$(openssl x509 -in "$idx_dir/certs/admin.pem" -noout -subject -nameopt RFC2253 \
    | sed 's/^subject=//' | tr -d ' ')"

  [[ "$idx_dn" == "CN=wazuh.indexer,OU=Wazuh,O=Wazuh,L=California,C=US" ]] || \
    die "Unexpected indexer certificate DN: $idx_dn"

  [[ "$admin_dn" == "CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US" ]] || \
    die "Unexpected admin certificate DN: $admin_dn"

  ok "Fresh Wazuh TLS certificates generated with image-matched ownership"
}
