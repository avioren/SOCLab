#!/usr/bin/env bash
set -Eeuo pipefail

BASE_SHA="${CI_MERGE_REQUEST_DIFF_BASE_SHA:-${CI_COMMIT_BEFORE_SHA:-}}"
HEAD_SHA="${CI_COMMIT_SHA:-HEAD}"

if [[ -z "$BASE_SHA" || "$BASE_SHA" =~ ^0+$ ]]; then
  echo "No usable base SHA; architecture impact check skipped."
  exit 0
fi

changed="$(git diff --name-only "$BASE_SHA" "$HEAD_SHA")"
printf '%s\n' "$changed"

architecture_sensitive='^(install\.sh|lib/|integrations/|detections/|docker/|compose/|\.gitlab-ci\.yml|mkdocs\.yml)'
architecture_docs='^docs/diagrams/'

if ! grep -Eq "$architecture_sensitive" <<<"$changed"; then
  echo "No architecture-sensitive implementation changes detected."
  exit 0
fi

if grep -Eq "$architecture_docs" <<<"$changed"; then
  echo "Architecture-sensitive change includes docs/diagrams update."
  exit 0
fi

cat >&2 <<'EOF'
Architecture-sensitive implementation changed without an architecture decision.
Update the versioned architecture documentation under docs/diagrams/ in this merge request.
If architecture is genuinely unchanged, add/update docs/diagrams/architecture-no-change.md with the reason.
EOF
exit 1
