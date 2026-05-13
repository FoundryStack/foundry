#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-$(elixir -e 'IO.write(Mix.Project.config()[:version])' 2>/dev/null || echo 0.1.0)}"
OUT_DIR="$ROOT_DIR/dist"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/SHA256SUMS

shopt -s nullglob
for artifact in "$ROOT_DIR"/burrito_out/*; do
  name="$(basename "$artifact")"
  archive="$OUT_DIR/foundry-v${VERSION}-${name}.tar.gz"
  tar -C "$(dirname "$artifact")" -czf "$archive" "$name"
done

(
  cd "$OUT_DIR"
  shasum -a 256 ./*.tar.gz > SHA256SUMS
)
