#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v node >/dev/null 2>&1; then
  echo "[ERROR] Node.js is required to render diagrams." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[ERROR] npm is required to render diagrams." >&2
  exit 1
fi

if [[ ! -f scripts/render-diagrams.mjs ]]; then
  echo "[ERROR] scripts/render-diagrams.mjs was not found." >&2
  exit 1
fi

if [[ ! -d docs/diagrams/src ]]; then
  echo "[ERROR] docs/diagrams/src was not found." >&2
  exit 1
fi

if [[ ! -d node_modules/beautiful-mermaid ]]; then
  echo "[INFO] Installing diagram renderer dependencies..."
  npm install --no-audit --no-fund
fi

echo "[INFO] Rendering SOCLab Mermaid diagrams..."
node scripts/render-diagrams.mjs

echo "[OK] Diagrams rendered successfully."
echo "[OK] Output: docs/diagrams/generated/"
