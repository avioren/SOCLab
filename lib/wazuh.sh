#!/usr/bin/env bash
# shellcheck shell=bash

patch_wazuh_dashboard_port() {
  local compose="$WAZUH_SINGLE/docker-compose.yml"
  python3 - "$compose" "$WAZUH_DASHBOARD_PORT" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
port = sys.argv[2]
text = p.read_text()
before = text
text = re.sub(r'(?m)^(\s*-\s*)"?443:5601"?\s*$', rf'\1"{port}:5601"', text)
text = re.sub(r'(?m)^(\s*-\s*)"?0\.0\.0\.0:443:5601"?\s*$', rf'\1"0.0.0.0:{port}:5601"', text)
if text == before and f"{port}:5601" not in text:
    raise SystemExit("Could not locate dashboard host port mapping 443:5601")
p.write_text(text)
PY
  ok "Wazuh dashboard mapped to https://localhost:${WAZUH_DASHBOARD_PORT}"
}

detect_wazuh_image_accounts() {
  phase "DETECT WAZUH BETA5 CONTAINER USERS"
  detect_one() {
    local image="$1" account="$2" out uid gid
    out="$(docker run --rm --entrypoint sh "$image" -lc "u=\$(id -u '$account' 2>/dev/null || id -u); g=\$(id -g '$account' 2>/dev/null || id -g); printf '%s:%s\n' \"\$u\" \"\$g\"")" || die "Could not determine UID/GID for $account in $image"
    uid="${out%%:*}"; gid="${out##*:}"
    [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || die "Unexpected UID/GID result for $account in $image: $out"
    printf '%s:%s' "$uid" "$gid"
  }
  local pair
  pair="$(detect_one "wazuh/wazuh-indexer:${WAZUH_VERSION}" "wazuh-indexer")"; WAZUH_INDEXER_UID="${pair%%:*}"; WAZUH_INDEXER_GID="${pair##*:}"
  pair="$(detect_one "wazuh/wazuh-manager:${WAZUH_VERSION}" "wazuh-manager")"; WAZUH_MANAGER_UID="${pair%%:*}"; WAZUH_MANAGER_GID="${pair##*:}"
  pair="$(detect_one "wazuh/wazuh-dashboard:${WAZUH_VERSION}" "wazuh-dashboard")"; WAZUH_DASHBOARD_UID="${pair%%:*}"; WAZUH_DASHBOARD_GID="${pair##*:}"
  log "beta5 indexer user:   ${WAZUH_INDEXER_UID}:${WAZUH_INDEXER_GID}"
  log "beta5 manager user:   ${WAZUH_MANAGER_UID}:${WAZUH_MANAGER_GID}"
  log "beta5 dashboard user: ${WAZUH_DASHBOARD_UID}:${WAZUH_DASHBOARD_GID}"
  ok "Detected service UID/GID values from the actual beta5 images"
}

generate_wazuh_certs_locally() {
  phase "PHASE 3/7 - GENERATE FRESH WAZUH 5 TLS CERTIFICATES"
  [[ -n "$WAZUH_INDEXER_UID" && -n "$WAZUH_MANAGER_UID" && -n "$WAZUH_DASHBOARD_UID" ]] || die "Service UID/GID values were not detected before certificate generation."
  local cfg="$WAZUH_SINGLE/config" ca_dir="$WAZUH_SINGLE/config/root-ca" idx_dir="$WAZUH_SINGLE/config/wazuh_indexer" mgr_dir="$WAZUH_SINGLE/config/wazuh_manager" dash_dir="$WAZUH_SINGLE/config/wazuh_dashboard"
  rm -rf "$ca_dir" "$idx_dir" "$mgr_dir" "$dash_dir"
  mkdir -p "$ca_dir/certs" "$ca_dir/private" "$idx_dir/certs" "$idx_dir/private" "$mgr_dir/certs" "$mgr_dir/private" "$dash_dir/certs" "$dash_dir/private"
  chmod 755 "$ca_dir" "$ca_dir/certs" "$idx_dir" "$idx_dir/certs" "$mgr_dir" "$mgr_dir/certs" "$dash_dir" "$dash_dir/certs"
  chmod 700 "$ca_dir/private" "$idx_dir/private" "$mgr_dir/private" "$dash_dir/private"
  local ca_key="$ca_dir/private/root-ca-key.pem" ca_cert="$ca_dir/certs/root-ca.pem"
  log "Generating root CA"
  openssl genrsa -out "$ca_key" 2048 >/dev/null 2>&1
  openssl req -x509 -new -nodes -key "$ca_key" -sha256 -days 3650 -out "$ca_cert" -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=Wazuh Root CA" >/dev/null 2>&1
  make_cert() {
    local filename="$1" dir="$2" cn="$3" san="$4" key="$2/certs/$1-key.pem" cert="$2/certs/$1.pem" csr="$2/private/$1.csr" ext="$2/private/$1.ext"
    log "Generating certificate: $filename"
    openssl genrsa -out "$key" 2048 >/dev/null 2>&1
    openssl req -new -key "$key" -out "$csr" -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=${cn}" >/dev/null 2>&1
    cat >"$ext" <<EOF
subjectAltName=${san}
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
EOF
    openssl x509 -req -in "$csr" -CA "$ca_cert" -CAkey "$ca_key" -CAcreateserial -out "$cert" -days 3650 -sha256 -extfile "$ext" >/dev/null 2>&1
    cp -f "$key" "$dir/private/${filename}-key.pem"
  }
  make_cert "wazuh.indexer" "$idx_dir" "wazuh.indexer" "DNS:wazuh.indexer,DNS:localhost,IP:127.0.0.1"
  make_cert "admin" "$idx_dir" "admin" "DNS:admin,DNS:localhost,IP:127.0.0.1"
  make_cert "wazuh.manager" "$mgr_dir" "wazuh.manager" "DNS:wazuh.manager,DNS:localhost,IP:127.0.0.1"
  make_cert "wazuh.dashboard" "$dash_dir" "wazuh.dashboard" "DNS:wazuh.dashboard,DNS:localhost,IP:127.0.0.1"
  chown root:root "$ca_cert" "$idx_dir/certs/wazuh.indexer.pem" "$idx_dir/certs/admin.pem" "$mgr_dir/certs/wazuh.manager.pem" "$dash_dir/certs/wazuh.dashboard.pem"
  chmod 644 "$ca_cert" "$idx_dir/certs/wazuh.indexer.pem" "$idx_dir/certs/admin.pem" "$mgr_dir/certs/wazuh.manager.pem" "$dash_dir/certs/wazuh.dashboard.pem"
  chown "${WAZUH_INDEXER_UID}:${WAZUH_INDEXER_GID}" "$idx_dir/certs/wazuh.indexer-key.pem" "$idx_dir/certs/admin-key.pem"; chmod 640 "$idx_dir/certs/wazuh.indexer-key.pem" "$idx_dir/certs/admin-key.pem"
  chown "${WAZUH_MANAGER_UID}:${WAZUH_MANAGER_GID}" "$mgr_dir/certs/wazuh.manager-key.pem"; chmod 640 "$mgr_dir/certs/wazuh.manager-key.pem"
  chown "${WAZUH_DASHBOARD_UID}:${WAZUH_DASHBOARD_GID}" "$dash_dir/certs/wazuh.dashboard-key.pem"; chmod 640 "$dash_dir/certs/wazuh.dashboard-key.pem"
  chmod 600 "$ca_key" "$idx_dir/private/"*.pem "$mgr_dir/private/"*.pem "$dash_dir/private/"*.pem 2>/dev/null || true
  local required=("$ca_dir/certs/root-ca.pem" "$idx_dir/certs/wazuh.indexer.pem" "$idx_dir/certs/wazuh.indexer-key.pem" "$idx_dir/certs/admin.pem" "$idx_dir/certs/admin-key.pem" "$mgr_dir/certs/wazuh.manager.pem" "$mgr_dir/certs/wazuh.manager-key.pem" "$dash_dir/certs/wazuh.dashboard.pem" "$dash_dir/certs/wazuh.dashboard-key.pem") f
  for f in "${required[@]}"; do [[ -s "$f" ]] || die "Missing generated certificate: $f"; done
  local idx_dn admin_dn
  idx_dn="$(openssl x509 -in "$idx_dir/certs/wazuh.indexer.pem" -noout -subject -nameopt RFC2253 | sed 's/^subject=//' | tr -d ' ')"
  admin_dn="$(openssl x509 -in "$idx_dir/certs/admin.pem" -noout -subject -nameopt RFC2253 | sed 's/^subject=//' | tr -d ' ')"
  [[ "$idx_dn" == "CN=wazuh.indexer,OU=Wazuh,O=Wazuh,L=California,C=US" ]] || die "Unexpected indexer certificate DN: $idx_dn"
  [[ "$admin_dn" == "CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US" ]] || die "Unexpected admin certificate DN: $admin_dn"
  ok "Fresh Wazuh TLS certificates generated with image-matched ownership"
}

verify_wazuh_cert_mounts() {
  phase "VERIFY CERTIFICATE MOUNTS BEFORE STARTUP"
  check_service_mounts() {
    local service="$1" uid="$2" gid="$3"; shift 3
    local test_cmd="id; " p
    for p in "$@"; do test_cmd+="echo CHECK:$p; ls -ln '$p'; test -r '$p' || exit 42; "; done
    log "Testing certificate readability for $service as UID:GID ${uid}:${gid}"
    if ! (cd "$WAZUH_SINGLE" && docker compose run --rm --no-deps --user "${uid}:${gid}" --entrypoint sh "$service" -lc "$test_cmd"); then
      find "$WAZUH_SINGLE/config" -maxdepth 4 -type f -name '*.pem' -printf '%m %u:%g %p\n' | sort || true
      die "Certificate mount/readability preflight failed for $service"
    fi
  }
  check_service_mounts "wazuh.indexer" "$WAZUH_INDEXER_UID" "$WAZUH_INDEXER_GID" "/usr/share/wazuh-indexer/config/certs/root-ca.pem" "/usr/share/wazuh-indexer/config/certs/indexer.pem" "/usr/share/wazuh-indexer/config/certs/indexer-key.pem" "/usr/share/wazuh-indexer/config/certs/admin.pem" "/usr/share/wazuh-indexer/config/certs/admin-key.pem"
  check_service_mounts "wazuh.manager" "$WAZUH_MANAGER_UID" "$WAZUH_MANAGER_GID" "/var/wazuh-manager/etc/certs/root-ca.pem" "/var/wazuh-manager/etc/certs/indexer-connector.pem" "/var/wazuh-manager/etc/certs/indexer-connector-key.pem"
  check_service_mounts "wazuh.dashboard" "$WAZUH_DASHBOARD_UID" "$WAZUH_DASHBOARD_GID" "/usr/share/wazuh-dashboard/config/certs/root-ca.pem" "/usr/share/wazuh-dashboard/config/certs/dashboard.pem" "/usr/share/wazuh-dashboard/config/certs/dashboard-key.pem"
  ok "All Wazuh certificate bind mounts are readable by their real beta5 service users"
}

generate_wazuh_password_hash() {
  local password="$1" hash
  hash="$(printf '%s\n' "$password" | docker run --rm -i --entrypoint bash "wazuh/wazuh-indexer:${WAZUH_VERSION}" -lc 'set -e; tool="$(find /usr/share/wazuh-indexer -type f -path "*/opensearch-security/tools/hash.sh" -print -quit)"; [ -n "$tool" ] || exit 9; bash "$tool" 2>/dev/null' | grep -E '\$2[aby]\$' | tail -1)"
  [[ "$hash" =~ ^\$2[aby]\$ ]] || die "Unable to generate Wazuh bcrypt password hash."
  printf '%s' "$hash"
}

patch_internal_user_hash() {
  local username="$1" hash="$2" file
  file="$(find "$WAZUH_SINGLE/config" -type f -name internal_users.yml -print -quit)"
  [[ -n "$file" && -f "$file" ]] || die "Wazuh internal_users.yml was not found."
  python3 - "$file" "$username" "$hash" <<'PY'
import pathlib, re, sys
path=pathlib.Path(sys.argv[1]); user=sys.argv[2]; new_hash=sys.argv[3]; lines=path.read_text().splitlines(True)
start=next((i for i,l in enumerate(lines) if re.match(rf'^{re.escape(user)}:\s*(?:#.*)?$',l.rstrip('\n'))),None)
if start is None: raise SystemExit(f"User {user!r} not found in {path}")
end=next((i for i in range(start+1,len(lines)) if re.match(r'^[A-Za-z0-9_.-]+:\s*(?:#.*)?$',lines[i].rstrip('\n'))),len(lines))
for i in range(start+1,end):
 m=re.match(r'^(\s+hash:\s*).*(\n?)$',lines[i])
 if m:
  lines[i]=f'{m.group(1)}"{new_hash}"{m.group(2)}'; path.write_text(''.join(lines)); break
else: raise SystemExit(f"hash field for {user!r} not found in {path}")
PY
}

configure_wazuh_runtime_credentials() {
  phase "CONFIGURE WAZUH RUNTIME CREDENTIALS"
  local admin_hash dashboard_hash env_file compose dashboard_cfg
  admin_hash="$(generate_wazuh_password_hash "$WAZUH_ADMIN_PASSWORD")"; dashboard_hash="$(generate_wazuh_password_hash "$WAZUH_DASHBOARD_SERVICE_PASSWORD")"
  patch_internal_user_hash "$WAZUH_ADMIN_USER" "$admin_hash"; patch_internal_user_hash "$WAZUH_DASHBOARD_SERVICE_USER" "$dashboard_hash"; unset admin_hash dashboard_hash
  env_file="$WAZUH_SINGLE/.env"
  cat >"$env_file" <<EOF
WAZUH_ADMIN_PASSWORD=${WAZUH_ADMIN_PASSWORD}
WAZUH_DASHBOARD_SERVICE_PASSWORD=${WAZUH_DASHBOARD_SERVICE_PASSWORD}
WAZUH_API_PASSWORD=${WAZUH_API_PASSWORD}
EOF
  chmod 600 "$env_file"
  compose="$WAZUH_SINGLE/docker-compose.yml"
  python3 - "$compose" <<'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1]); text=p.read_text(); blocks=re.split(r'(?m)(?=^  [A-Za-z0-9_.-]+:\s*$)',text); seen={"admin":0,"kibana":0,"api":0}; out=[]
for block in blocks:
 if 'INDEXER_USERNAME=admin' in block: block,n=re.subn(r'(?m)^(\s*-\s*INDEXER_PASSWORD=).+$',r'\1${WAZUH_ADMIN_PASSWORD}',block); seen['admin']+=n
 if 'DASHBOARD_USERNAME=kibanaserver' in block: block,n=re.subn(r'(?m)^(\s*-\s*DASHBOARD_PASSWORD=).+$',r'\1${WAZUH_DASHBOARD_SERVICE_PASSWORD}',block); seen['kibana']+=n
 if 'API_USERNAME=wazuh-wui' in block: block,n=re.subn(r'(?m)^(\s*-\s*API_PASSWORD=).+$',r'\1${WAZUH_API_PASSWORD}',block); seen['api']+=n
 out.append(block)
p.write_text(''.join(out)); print(f"credential placeholders configured: admin={seen['admin']} kibanaserver={seen['kibana']} api={seen['api']}")
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
   if re.match(r'password:\s*',stripped): lines[j]=lines[j][:indent]+f'password: "{password}"\n'; updated=True; break
p.write_text(''.join(lines))
if not updated: print('wazuh.yml did not contain a wazuh-wui password field; Compose/runtime may provide it instead')
PY
    chmod 600 "$dashboard_cfg"
  fi
  (cd "$WAZUH_SINGLE" && docker compose config --quiet)
  ok "Wazuh runtime credentials configured without logging secret values"
}

verify_runtime_credentials() {
  local code token
  code="$(curl -ksS -o /tmp/soclab-admin-auth.out -w '%{http_code}' --max-time 10 -u "${WAZUH_ADMIN_USER}:${WAZUH_ADMIN_PASSWORD}" https://localhost:9200/ || true)"
  [[ "$code" == "200" ]] || die "Wazuh admin/indexer credential verification failed (HTTP ${code:-none})."
  ok "Wazuh admin/indexer credential authenticated successfully"
  token="$(curl -ksS --max-time 15 -u "${WAZUH_API_USER}:${WAZUH_API_PASSWORD}" -X POST 'https://localhost:55000/security/user/authenticate?raw=true' || true)"
  [[ -n "$token" && "$token" != *'error'* && "$token" != *'Unauthorized'* ]] || die "Wazuh API credential verification failed for ${WAZUH_API_USER}."
  unset token
  ok "Wazuh API credential authenticated successfully"
}

compose_service_id() { local service="$1"; (cd "$WAZUH_SINGLE" && docker compose ps -q --all "$service" 2>/dev/null | head -1); }
compose_service_name() { local service="$1" id; id="$(compose_service_id "$service")"; [[ -n "$id" ]] || return 1; docker inspect -f '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##'; }
compose_service_running() { local service="$1" id; id="$(compose_service_id "$service")"; [[ -n "$id" ]] || return 1; [[ "$(docker inspect -f '{{.State.Running}}' "$id" 2>/dev/null || echo false)" == "true" ]]; }
compose_service_health() { local service="$1" id; id="$(compose_service_id "$service")"; [[ -n "$id" ]] || { echo missing; return; }; docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id" 2>/dev/null || echo missing; }

wait_wazuh_service() {
  local service="$1" timeout="$2" start now health name
  start="$(date +%s)"
  while true; do
    health="$(compose_service_health "$service")"
    if compose_service_running "$service" && [[ "$health" == "healthy" || "$health" == "none" ]]; then name="$(compose_service_name "$service" || echo "$service")"; ok "$service ready: container=$name health=$health"; return 0; fi
    now="$(date +%s)"; if (( now-start>=timeout )); then warn "$service readiness timeout; last health=$health"; return 1; fi
    sleep 8
  done
}

dump_wazuh_diagnostics() {
  echo; log "===== WAZUH COMPOSE STATUS ====="; (cd "$WAZUH_SINGLE" && docker compose ps -a) || true
  local service id
  for service in wazuh.indexer wazuh.manager wazuh.dashboard; do
    id="$(compose_service_id "$service" || true)"
    if [[ -n "$id" ]]; then echo; log "===== $service / $(compose_service_name "$service" || echo "$id") ====="; docker inspect "$id" --format 'running={{.State.Running}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} exit={{.State.ExitCode}}' 2>/dev/null || true; docker logs --tail 300 "$id" 2>&1 || true; else warn "No container found for Compose service $service"; fi
  done
}
