#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

fail=0

report_matches() {
  local title="$1" pattern="$2"
  local out
  out="$(grep -RInE \
    --exclude-dir=.git \
    --exclude-dir=public \
    --exclude-dir=public-check \
    --exclude='*.zip' \
    --exclude='check-secrets.sh' \
    "$pattern" . 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    echo "[FAIL] $title"
    echo "$out"
    fail=1
  fi
}

report_matches "Private key material detected" 'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY'
report_matches "GitLab token detected" 'glpat-[A-Za-z0-9_-]{10,}'
report_matches "GitHub token detected" '(ghp_|github_pat_)[A-Za-z0-9_]{10,}'
report_matches "AWS access key detected" 'AKIA[0-9A-Z]{16}'
report_matches "Bearer token detected" 'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._~+/-]{10,}'

# Inspect credential-like assignments. Runtime expressions are allowed; literal
# values are blocked. This is intentionally conservative for repository safety.
assignment_key_pattern='(^|[^A-Za-z0-9_])(PASSWORD|PASSWD|TOKEN|SECRET|APIKEY|API_KEY)[A-Za-z0-9_]*[[:space:]]*='
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  rest="${line#*:}"
  lineno="${rest%%:*}"
  value="${rest#*:}"

  # Ignore comments and runtime-generated/runtime-expanded values.
  trimmed="${value#"${value%%[![:space:]]*}"}"
  [[ "$trimmed" == \#* ]] && continue
  [[ "$value" == *'${'* || "$value" == *'$('* ]] && continue

  # Ignore empty assignments and explicit non-secret placeholders.
  rhs="${value#*=}"
  rhs="${rhs#"${rhs%%[![:space:]]*}"}"
  rhs="${rhs%"${rhs##*[![:space:]]}"}"
  rhs="${rhs%\"}"; rhs="${rhs#\"}"
  rhs="${rhs%\'}"; rhs="${rhs#\'}"
  [[ -z "$rhs" ]] && continue
  case "${rhs^^}" in
    REDACTED|CHANGEME|CHANGE_ME|EXAMPLE|PLACEHOLDER|NOT_SET|UNSET) continue ;;
  esac

  echo "[FAIL] Literal credential-like assignment detected: ${file}:${lineno}"
  echo "$value"
  fail=1
done < <(grep -RInE \
  --exclude-dir=.git \
  --exclude-dir=public \
  --exclude-dir=public-check \
  --exclude='*.zip' \
  --exclude='check-secrets.sh' \
  "$assignment_key_pattern" . 2>/dev/null || true)

while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  echo "[FAIL] Secret-bearing file should not be tracked/published: $f"
  fail=1
done < <(find . -type f \
  \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.key' \
     -o -name '*.p12' -o -name '*.pfx' -o -name 'credentials.txt' \) \
  -not -path './.git/*' -print)

if (( fail )); then
  echo "Secret safety check FAILED"
  exit 1
fi

echo "Secret safety check PASSED"
