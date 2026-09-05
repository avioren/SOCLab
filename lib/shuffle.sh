#!/usr/bin/env bash
# shellcheck shell=bash

upsert_env() {
  local file="$1" key="$2" value="$3"
  touch "$file"

  if grep -qE "^${key}=" "$file"; then
    local escaped
    escaped="$(printf '%s' "$value" | sed 's/[&|]/\\&/g')"
    sed -i "s|^~^${key}=.*|${key}=${escaped}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

patch_shuffle_compose() {
  local compose="$SHUFFLE_DIR/docker-compose.yml"

  python3 - "$compose" "$SHUFFLE_OPENSEARCH_PORT" <<'PY'
import pathlib, re, sys

p = pathlib.Path(sys.argv[1])
port = sys.argv[2]
text = p.read_text()

text = re.sub(
    r'(?m)^(\s*-\s*)"?: