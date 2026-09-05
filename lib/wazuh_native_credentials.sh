#!/usr/bin/env bash
# shellcheck shell=bash

WAZUH_BOOTSTRAP_ADMIN_PASSWORD=""
WAZUH_BOOTSTRAP_DASHBOARD_PASSWORD=""
WAZUH_BOOTSTRAP_API_PASSWORD=""

# Replace only installer-owned certificate directories. Do not touch or assume
# the presence of internal_users.yml or other Wazuh security configuration.
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
  ok "Fresh Wazuh TLS certificates generated without modifying Wazuh security user files"
}

capture_wazuh_bootstrap_credentials() {
  local cfg
  log "Reading stock beta5 bootstrap credentials from the cloned Compose model (values are not logged)"
  cfg="$(cd "$WAZUH_SINGLE" && docker compose config --format json)" || \
    die "Could not render Wazuh Compose config as JSON."

  WAZUH_BOOTSTRAP_ADMIN_PASSWORD="$(printf '%s' "$cfg" | jq -r '.services["wazuh.manager"].environment.INDEXER_PASSWORD // empty')"
  WAZUH_BOOTSTRAP_DASHBOARD_PASSWORD="$(printf '%s' "$cfg" | jq -r '.services["wazuh.dashboard"].environment.DASHBOARD_PASSWORD // empty')"
  WAZUH_BOOTSTRAP_API_PASSWORD="$(printf '%s' "$cfg" | jq -r '.services["wazuh.manager"].environment.API_PASSWORD // .services["wazuh.dashboard"].environment.API_PASSWORD // empty')"
  unset cfg

  [[ -n "$WAZUH_BOOTSTRAP_ADMIN_PASSWORD" ]] || die "Could not discover stock beta5 INDEXER_PASSWORD."
  [[ -n "$WAZUH_BOOTSTRAP_DASHBOARD_PASSWORD" ]] || die "Could not discover stock beta5 DASHBOARD_PASSWORD."
  [[ -n "$WAZUH_BOOTSTRAP_API_PASSWORD" ]] || die "Could not discover stock beta5 API_PASSWORD."
  ok "Stock beta5 bootstrap credentials discovered in memory"
}

rotate_indexer_user_password() {
  local username="$1" password="$2" indexer_id output
  indexer_id="$(compose_service_id wazuh.indexer)"
  [[ -n "$indexer_id" ]] || die "Wazuh indexer container was not found for credential rotation."
  output="$(mktemp /tmp/soclab-wazuh-password-tool.XXXXXX)"
  chmod 600 "$output"

  if ! printf '%s\n' "$password" | docker exec -i -u 0 "$indexer_id" bash -lc '
      set -euo pipefail
      export JAVA_HOME=/usr/share/wazuh-indexer/jdk
      export PATH="$JAVA_HOME/bin:$PATH"
      target_user="$1"
      IFS= read -r new_password
      tool=/usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-passwords-tool.sh
      if [ ! -f "$tool" ]; then
        tool="$(find /usr/share/wazuh-indexer -type f -name wazuh-passwords-tool.sh -print -quit)"
      fi
      [ -n "$tool" ] && [ -f "$tool" ]
      bash "$tool" -u "$target_user" -p "$new_password"
    ' _ "$username" >"$output" 2>&1; then
    rm -f "$output"
    die "Wazuh native password tool failed while rotating indexer user ${username}; secret output was not logged."
  fi

  rm -f "$output"
  ok "Wazuh native password tool rotated indexer user ${username}"
}

api_request_with_token() {
  local token="$1" method="$2" url="$3" body_file="${4:-}" output_file="$5"
  local cfg
  cfg="$(mktemp /tmp/soclab-curl-auth.XXXXXX)"
  chmod 600 "$cfg"
  printf 'header = "Authorization: Bearer %s"\n' "$token" >"$cfg"
  if [[ -n "$body_file" ]]; then
    curl -ksS --max-time 20 --config "$cfg" -X "$method" \
      -H 'Content-Type: application/json' --data-binary "@$body_file" \
      -o "$output_file" -w '%{http_code}' "$url"
  else
    curl -ksS --max-time 20 --config "$cfg" -X "$method" \
      -o "$output_file" -w '%{http_code}' "$url"
  fi
  rm -f "$cfg"
}

rotate_wazuh_api_password() {
  local netrc auth_out token users_out user_id body_out body_file code
  netrc="$(mktemp /tmp/soclab-wazuh-api-netrc.XXXXXX)"
  auth_out="$(mktemp /tmp/soclab-wazuh-api-auth.XXXXXX)"
  users_out="$(mktemp /tmp/soclab-wazuh-api-users.XXXXXX)"
  body_out="$(mktemp /tmp/soclab-wazuh-api-update.XXXXXX)"
  body_file="$(mktemp /tmp/soclab-wazuh-api-body.XXXXXX)"
  chmod 600 "$netrc" "$auth_out" "$users_out" "$body_out" "$body_file"

  printf 'machine localhost login %s password %s\n' "$WAZUH_API_USER" "$WAZUH_BOOTSTRAP_API_PASSWORD" >"$netrc"
  token="$(curl -ksS --max-time 20 --netrc-file "$netrc" \
    -X POST 'https://localhost:55000/security/user/authenticate?raw=true' || true)"
  rm -f "$netrc" "$auth_out"
  [[ -n "$token" && "$token" != *'error'* && "$token" != *'Unauthorized'* ]] || {
    rm -f "$users_out" "$body_out" "$body_file"
    die "Could not authenticate to the stock Wazuh API for password rotation."
  }

  code="$(api_request_with_token "$token" GET 'https://localhost:55000/security/users?pretty=true' '' "$users_out" || true)"
  [[ "$code" == "200" ]] || {
    rm -f "$users_out" "$body_out" "$body_file"
    unset token
    die "Could not list Wazuh API users during credential rotation (HTTP ${code:-none})."
  }

  user_id="$(jq -r --arg user "$WAZUH_API_USER" '.data.affected_items[]? | select(.username == $user) | .id' "$users_out" | head -1)"
  [[ "$user_id" =~ ^[0-9]+$ ]] || {
    rm -f "$users_out" "$body_out" "$body_file"
    unset token
    die "Could not locate API user ${WAZUH_API_USER} by ID."
  }

  NEW_WAZUH_API_PASSWORD="$WAZUH_API_PASSWORD" jq -n '{password: env.NEW_WAZUH_API_PASSWORD}' >"$body_file"
  code="$(api_request_with_token "$token" PUT "https://localhost:55000/security/users/${user_id}" "$body_file" "$body_out" || true)"
  rm -f "$users_out" "$body_out" "$body_file"
  unset token
  [[ "$code" == "200" ]] || die "Wazuh API rejected password rotation for ${WAZUH_API_USER} (HTTP ${code:-none})."
  ok "Wazuh API password rotated using the supported REST API"
}

apply_wazuh_client_credentials() {
  local env_file="$WAZUH_SINGLE/.env" compose="$WAZUH_SINGLE/docker-compose.yml" dashboard_cfg

  cat >"$env_file" <<EOF
WAZUH_ADMIN_PASSWORD=${WAZUH_ADMIN_PASSWORD}
WAZUH_DASHBOARD_SERVICE_PASSWORD=${WAZUH_DASHBOARD_SERVICE_PASSWORD}
WAZUH_API_PASSWORD=${WAZUH_API_PASSWORD}
EOF
  chmod 600 "$env_file"

  python3 - "$compose" <<'PY'
import pathlib, re, sys
p=pathlib.Path(sys.argv[1]); text=p.read_text(); blocks=re.split(r'(?m)(?=^  [A-Za-z0-9_.-]+:\s*$)',text); seen={"admin":0,"kibana":0,"api":0}; out=[]
for block in blocks:
    if 'INDEXER_USERNAME=admin' in block:
        block,n=re.subn(r'(?m)^(\s*-\s*INDEXER_PASSWORD=).+$',r'\1${WAZUH_ADMIN_PASSWORD}',block); seen['admin']+=n
    if 'DASHBOARD_USERNAME=kibanaserver' in block:
        block,n=re.subn(r'(?m)^(\s*-\s*DASHBOARD_PASSWORD=).+$',r'\1${WAZUH_DASHBOARD_SERVICE_PASSWORD}',block); seen['kibana']+=n
    if 'API_USERNAME=wazuh-wui' in block:
        block,n=re.subn(r'(?m)^(\s*-\s*API_PASSWORD=).+$',r'\1${WAZUH_API_PASSWORD}',block); seen['api']+=n
    out.append(block)
if not all(seen.values()):
    raise SystemExit(f"Could not patch all Wazuh client credential references: {seen}")
p.write_text(''.join(out))
print(f"credential references updated: admin={seen['admin']} kibanaserver={seen['kibana']} api={seen['api']}")
PY

  dashboard_cfg="$WAZUH_SINGLE/config/wazuh_dashboard/wazuh.yml"
  if [[ -f "$dashboard_cfg" ]]; then
    WAZUH_API_PASSWORD_LOCAL="$WAZUH_API_PASSWORD" python3 - "$dashboard_cfg" <<'PY'
import os,pathlib,re,sys
p=pathlib.Path(sys.argv[1]); password=os.environ['WAZUH_API_PASSWORD_LOCAL']; lines=p.read_text().splitlines(True); updated=False
for i,line in enumerate(lines):
    if re.search(r'username:\s*["\x27]?wazuh-wui["\x27]?\s*$',line):
        base=len(line)-len(line.lstrip())
        for j in range(i+1,min(i+12,len(lines))):
            stripped=lines[j].lstrip(); indent=len(lines[j])-len(stripped)
            if indent<base and stripped.strip(): break
            if re.match(r'password:\s*',stripped):
                lines[j]=lines[j][:indent]+f'password: "{password}"\n'; updated=True; break
p.write_text(''.join(lines))
PY
    chmod 600 "$dashboard_cfg"
  fi

  (cd "$WAZUH_SINGLE" && docker compose config --quiet) || \
    die "Wazuh Compose validation failed after applying rotated credentials."
  ok "Wazuh manager/dashboard client configuration updated with rotated credentials"
}

rotate_wazuh_runtime_credentials() {
  phase "ROTATE WAZUH CREDENTIALS USING NATIVE INTERFACES"
  rotate_indexer_user_password "$WAZUH_ADMIN_USER" "$WAZUH_ADMIN_PASSWORD"
  rotate_indexer_user_password "$WAZUH_DASHBOARD_SERVICE_USER" "$WAZUH_DASHBOARD_SERVICE_PASSWORD"
  rotate_wazuh_api_password
  apply_wazuh_client_credentials

  log "Recreating Wazuh manager and dashboard with rotated credentials"
  (cd "$WAZUH_SINGLE" && docker compose up -d --no-deps --force-recreate wazuh.manager wazuh.dashboard) || \
    die "Could not recreate Wazuh manager/dashboard after credential rotation."

  wait_wazuh_service "wazuh.manager" 420 || { dump_wazuh_diagnostics; die "Wazuh manager did not recover after credential rotation."; }
  wait_wazuh_service "wazuh.dashboard" 420 || { dump_wazuh_diagnostics; die "Wazuh dashboard did not recover after credential rotation."; }

  unset WAZUH_BOOTSTRAP_ADMIN_PASSWORD WAZUH_BOOTSTRAP_DASHBOARD_PASSWORD WAZUH_BOOTSTRAP_API_PASSWORD
  ok "Wazuh credential rotation completed"
}
