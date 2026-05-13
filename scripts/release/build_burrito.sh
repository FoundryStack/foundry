#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-}"
REQUIRED_ZIG_VERSION="0.15.2"

cd "$ROOT_DIR"

for candidate in /opt/homebrew/opt/zig/bin /opt/homebrew/opt/xz/bin; do
  if [[ -d "$candidate" && ":$PATH:" != *":$candidate:"* ]]; then
    export PATH="$candidate:$PATH"
  fi
done

ensure_burrito_zig() {
  local current_version=""

  if command -v zig >/dev/null 2>&1; then
    current_version="$(zig version 2>/dev/null || true)"
  fi

  if [[ "$current_version" == "$REQUIRED_ZIG_VERSION" ]]; then
    return 0
  fi

  local platform archive host_triple install_root archive_path download_url
  local uname_s uname_m

  uname_s="$(uname -s)"
  uname_m="$(uname -m)"

  case "${uname_s}:${uname_m}" in
    Darwin:arm64)
      archive="zig-aarch64-macos-${REQUIRED_ZIG_VERSION}.tar.xz"
      host_triple="aarch64-macos"
      ;;
    Darwin:x86_64)
      archive="zig-x86_64-macos-${REQUIRED_ZIG_VERSION}.tar.xz"
      host_triple="x86_64-macos"
      ;;
    Linux:x86_64)
      archive="zig-x86_64-linux-${REQUIRED_ZIG_VERSION}.tar.xz"
      host_triple="x86_64-linux"
      ;;
    *)
      echo "Unsupported host platform for Zig bootstrap: ${uname_s} ${uname_m}" >&2
      exit 1
      ;;
  esac

  install_root="${ROOT_DIR}/.foundry/tools/zig/${REQUIRED_ZIG_VERSION}/${host_triple}"
  archive_path="${install_root}/${archive}"
  download_url="https://ziglang.org/download/${REQUIRED_ZIG_VERSION}/${archive}"

  if [[ ! -x "${install_root}/${archive%.tar.xz}/zig" ]]; then
    mkdir -p "$install_root"

    if [[ ! -f "$archive_path" ]]; then
      curl -L "$download_url" -o "$archive_path"
    fi

    tar -xJf "$archive_path" -C "$install_root"
  fi

  export PATH="${install_root}/${archive%.tar.xz}:$PATH"
}

ensure_burrito_zig

export MIX_ENV=prod
export PHX_SERVER=true
export FOUNDRY_STANDALONE=1

mix deps.get
mix compile
mix cmd --app foundry_web mix assets.deploy

if [[ -n "$TARGET" ]]; then
  BURRITO_TARGET="$TARGET" mix release --overwrite foundry
else
  mix release --overwrite foundry
fi
