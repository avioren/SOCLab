#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/docs/diagrams/source"
OUTPUT_DIR="$ROOT_DIR/docs/diagrams/generated"
IMAGE="soclab-beautiful-mermaid:1.1.3"
MODE="render"

case "${1:-}" in
  "") ;;
  --check) MODE="check" ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

command -v docker >/dev/null 2>&1 || { echo "[FAIL] Docker is required" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "[FAIL] Docker daemon is not reachable" >&2; exit 1; }

shopt -s nullglob
source_paths=("$SOURCE_DIR"/*.mmd)
(( ${#source_paths[@]} > 0 )) || { echo "[FAIL] No .mmd diagram sources found" >&2; exit 1; }
mapfile -t sources < <(printf '%s\n' "${source_paths[@]##*/}" | sort)

echo "[OK] Docker reachable"
echo "[INFO] Building Beautiful Mermaid 1.1.3 renderer"
docker build -q -t "$IMAGE" "$ROOT_DIR/tools/diagrams" >/dev/null

if [[ "$MODE" == "check" ]]; then
  target="$(mktemp -d)"
  trap 'rm -rf "$target"' EXIT
else
  mkdir -p "$OUTPUT_DIR"
  target="$OUTPUT_DIR"
fi

for source in "${sources[@]}"; do
  output="${source%.mmd}.svg"
  docker run --rm \
    -v "$ROOT_DIR:/work:ro" \
    -v "$target:/output" \
    "$IMAGE" "/work/docs/diagrams/source/$source" "/output/$output" >/dev/null
  echo "[OK] $source -> $output"
done

if [[ "$MODE" == "check" ]]; then
  echo "[OK] All diagram sources render successfully; repository files unchanged"
else
  echo "[OK] SVGs written to docs/diagrams/generated/"
fi
