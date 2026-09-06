#!/usr/bin/env bash
set -Eeuo pipefail

SHUFFLE_DIR="${SHUFFLE_DIR:-/opt/soclab/Shuffle}"
ENV_FILE="$SHUFFLE_DIR/.env"
BACKEND_PORT="${SHUFFLE_BACKEND_PORT:-5001}"
OPENSEARCH_PORT="${SHUFFLE_OPENSEARCH_PORT:-9201}"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
ok() { log "[OK] $*"; }
die() { log "[FAIL] $*" >&2; exit 1; }

[[ -r "$ENV_FILE" ]] || die "Shuffle env file is not readable: $ENV_FILE"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

env_value() {
  local key="$1"
  sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n1
}

OS_USER="$(env_value SHUFFLE_OPENSEARCH_USERNAME)"
OS_PASS="$(env_value SHUFFLE_OPENSEARCH_PASSWORD)"
API_KEY="$(env_value SHUFFLE_DEFAULT_APIKEY)"

[[ -n "$OS_USER" ]] || OS_USER="admin"
[[ -n "$OS_PASS" ]] || die "SHUFFLE_OPENSEARCH_PASSWORD missing from $ENV_FILE"
[[ -n "$API_KEY" ]] || die "SHUFFLE_DEFAULT_APIKEY missing from $ENV_FILE"

OS_URL="https://localhost:${OPENSEARCH_PORT}"
API_URL="http://localhost:${BACKEND_PORT}/api/v1"

log "Checking Shuffle backend and OpenSearch"
curl -fsS --max-time 10 "$API_URL/checkusers" >/dev/null || die "Shuffle backend is not reachable on $API_URL"
curl -kfsS --max-time 10 -u "$OS_USER:$OS_PASS" "$OS_URL/_cluster/health" >/dev/null || die "Shuffle OpenSearch authentication/health failed"

log "Applying single-node workflow consistency settings"
for pattern in 'workflow-*' 'workflow_revisions-*' 'org_cache-*' 'org_cache_revisions-*'; do
  response="$(curl -ksS --max-time 20 -u "$OS_USER:$OS_PASS" \
    -X PUT "$OS_URL/${pattern}/_settings?allow_no_indices=true&ignore_unavailable=true" \
    -H 'Content-Type: application/json' \
    -d '{"index":{"refresh_interval":"1s","number_of_replicas":0}}')"
  if ! jq -e '.acknowledged == true' <<<"$response" >/dev/null 2>&1; then
    die "OpenSearch rejected settings for ${pattern}: $response"
  fi
done

curl -ksS --max-time 20 -u "$OS_USER:$OS_PASS" -X POST \
  "$OS_URL/workflow-*,workflow_revisions-*,org_cache-*,org_cache_revisions-*/_refresh?allow_no_indices=true&ignore_unavailable=true" \
  >/dev/null || die "OpenSearch refresh failed"

settings="$(curl -ksS --max-time 20 -u "$OS_USER:$OS_PASS" \
  "$OS_URL/workflow-*,org_cache-*/_settings?allow_no_indices=true&ignore_unavailable=true&filter_path=*.settings.index.refresh_interval,*.settings.index.number_of_replicas")"
if ! jq -e 'to_entries | length > 0 and all(.[]; .value.settings.index.refresh_interval == "1s" and .value.settings.index.number_of_replicas == "0")' <<<"$settings" >/dev/null; then
  die "Workflow/cache index settings were not applied consistently: $settings"
fi
ok "Workflow/cache indexes use refresh_interval=1s and replicas=0"

name="SOCLAB_CRUD_TEST_$(date +%s)_$RANDOM"
create_body="$(jq -cn --arg name "$name" '{name:$name,description:"SOCLab workflow CRUD health gate"}')"
log "Creating disposable workflow through Shuffle API"
create_resp="$(curl -fsS --max-time 20 -X POST "$API_URL/workflows" \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  --data "$create_body")" || die "Workflow CREATE request failed"
wf_id="$(jq -r '.id // empty' <<<"$create_resp")"
[[ -n "$wf_id" ]] || die "Workflow CREATE returned no id: $create_resp"

cleanup_workflow() {
  curl -sS --max-time 10 -X DELETE "$API_URL/workflows/$wf_id" \
    -H "Authorization: Bearer $API_KEY" >/dev/null 2>&1 || true
}
trap cleanup_workflow EXIT

sleep 2
get_code="$(curl -sS -o /tmp/soclab-workflow-get.json -w '%{http_code}' --max-time 20 \
  "$API_URL/workflows/$wf_id" -H "Authorization: Bearer $API_KEY" || true)"
[[ "$get_code" == "200" ]] || die "Workflow GET failed after create (HTTP $get_code): $(cat /tmp/soclab-workflow-get.json 2>/dev/null || true)"
[[ "$(jq -r '.id // empty' /tmp/soclab-workflow-get.json 2>/dev/null)" == "$wf_id" ]] || die "Workflow GET returned the wrong workflow"

list_resp="$(curl -fsS --max-time 20 "$API_URL/workflows" -H "Authorization: Bearer $API_KEY")" || die "Workflow LIST failed after create"
if ! jq -e --arg id "$wf_id" 'if type=="array" then any(.[]; .id==$id) else any((.workflows // [])[]; .id==$id) end' <<<"$list_resp" >/dev/null; then
  die "Workflow was created but is missing from LIST after 2 seconds"
fi
ok "Workflow CREATE/GET/LIST are consistent"

log "Deleting disposable workflow through Shuffle API"
delete_resp="$(curl -fsS --max-time 20 -X DELETE "$API_URL/workflows/$wf_id" \
  -H "Authorization: Bearer $API_KEY")" || die "Workflow DELETE request failed"
if ! jq -e '.success == true' <<<"$delete_resp" >/dev/null 2>&1; then
  die "Workflow DELETE did not report success: $delete_resp"
fi

curl -ksS --max-time 20 -u "$OS_USER:$OS_PASS" -X POST \
  "$OS_URL/workflow-*/_refresh?allow_no_indices=true&ignore_unavailable=true" >/dev/null || die "Workflow index refresh failed after delete"
sleep 2

list_resp="$(curl -fsS --max-time 20 "$API_URL/workflows" -H "Authorization: Bearer $API_KEY")" || die "Workflow LIST failed after delete"
if jq -e --arg id "$wf_id" 'if type=="array" then any(.[]; .id==$id) else any((.workflows // [])[]; .id==$id) end' <<<"$list_resp" >/dev/null; then
  die "Workflow DELETE reported success but workflow is still returned by LIST"
fi
trap - EXIT
ok "Workflow DELETE is visible to LIST; no stale workflow remains"

if docker inspect shuffle-backend >/dev/null 2>&1; then
  if docker logs --since 2m shuffle-backend 2>&1 | grep -Eqi 'all shards failed|search_phase_execution_exception'; then
    die "Recent Shuffle backend logs contain OpenSearch shard/search failures"
  fi
fi

ok "SHUFFLE WORKFLOW CRUD GATE PASSED"
printf '\nShuffle workflow storage is operational. Refresh the browser with Ctrl+Shift+R and create a real workflow.\n'
