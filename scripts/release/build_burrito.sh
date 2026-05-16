#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-}"
REQUIRED_ZIG_VERSION="${REQUIRED_ZIG_VERSION:-0.15.2}"

cd "$ROOT_DIR"

prepend_path() {
  local candidate="$1"

  if [[ -d "$candidate" && ":$PATH:" != *":$candidate:"* ]]; then
    export PATH="$candidate:$PATH"
  fi
}

for candidate in \
  /opt/homebrew/opt/zig/bin \
  /opt/homebrew/opt/zig@0.15/bin \
  /opt/homebrew/opt/xz/bin \
  /usr/local/opt/zig/bin \
  /usr/local/opt/zig@0.15/bin
do
  prepend_path "$candidate"
done

zig_smoke_test() {
  local zig_bin="${1:-zig}"
  local cache_root global_cache local_cache

  cache_root="$(mktemp -d "${TMPDIR:-/tmp}/foundry-burrito-zig.XXXXXX")"
  global_cache="${cache_root}/global"
  local_cache="${cache_root}/local"

  mkdir -p "$global_cache" "$local_cache"

  if env \
    ZIG_GLOBAL_CACHE_DIR="$global_cache" \
    ZIG_LOCAL_CACHE_DIR="$local_cache" \
    "$zig_bin" libc >/dev/null 2>&1; then
    rm -rf "$cache_root"
    return 0
  fi

  rm -rf "$cache_root"
  return 1
}

zig_version() {
  local zig_bin="${1:-zig}"
  "$zig_bin" version 2>/dev/null || true
}

zig_matches_required_version() {
  local zig_bin="${1:-zig}"
  [[ "$(zig_version "$zig_bin")" == "$REQUIRED_ZIG_VERSION" ]]
}

use_zig_binary() {
  local zig_bin="$1"
  local zig_dir

  zig_dir="$(cd "$(dirname "$zig_bin")" && pwd)"
  prepend_path "$zig_dir"
}

download_bundled_zig() {
  local archive="$1"
  local host_triple="$2"
  local install_root archive_path download_url

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

  printf '%s\n' "${install_root}/${archive%.tar.xz}/zig"
}

ensure_burrito_zig_on_darwin() {
  local archive="$1"
  local host_triple="$2"
  local -a candidates=()
  local zig_bin vendored_zig
  local candidate_override

  if zig_bin="$(command -v zig 2>/dev/null)"; then
    candidates+=("$zig_bin")
  fi

  if [[ -n "${FOUNDRY_BURRITO_ZIG_CANDIDATES:-}" ]]; then
    IFS=':' read -r -a candidate_override <<< "${FOUNDRY_BURRITO_ZIG_CANDIDATES}"
  else
    candidate_override=(
      /opt/homebrew/opt/zig@0.15/bin/zig
      /opt/homebrew/bin/zig
      /usr/local/opt/zig@0.15/bin/zig
      /usr/local/bin/zig
    )
  fi

  for zig_bin in "${candidate_override[@]}"; do
    [[ -x "$zig_bin" ]] || continue

    if [[ " ${candidates[*]} " != *" ${zig_bin} "* ]]; then
      candidates+=("$zig_bin")
    fi
  done

  for zig_bin in "${candidates[@]}"; do
    zig_matches_required_version "$zig_bin" || continue

    if zig_smoke_test "$zig_bin"; then
      use_zig_binary "$zig_bin"
      return 0
    fi
  done

  vendored_zig="$(download_bundled_zig "$archive" "$host_triple")"

  if zig_smoke_test "$vendored_zig"; then
    use_zig_binary "$vendored_zig"
    return 0
  fi

  echo "The bundled Zig ${REQUIRED_ZIG_VERSION} is not compatible with the current macOS toolchain." >&2
  echo "Burrito 1.5.0 requires Zig ${REQUIRED_ZIG_VERSION}; Zig 0.16.x is not supported for this build." >&2
  echo "Install a patched Homebrew Zig ${REQUIRED_ZIG_VERSION} with \`brew install zig@0.15\` and rerun the release build." >&2
  exit 1
}

verify_secret_key_base_config() {
  # Plug cookie store requires SECRET_KEY_BASE to be at least 64 bytes
  # Check that the fallback in config/runtime.exs meets this requirement
  local runtime_exs="${1:-$ROOT_DIR/config/runtime.exs}"

  if [[ ! -f "$runtime_exs" ]]; then
    return 0  # File doesn't exist, skip check
  fi

  # Extract all quoted strings that look like secrets from the standalone_mode block
  # Look for the pattern after "if standalone_mode? do"
  local fallback_secret
  fallback_secret=$(awk '/if standalone_mode\? do/,/else/' "$runtime_exs" | \
    grep -o '"[^"]*"' | \
    sed 's/"//g' | \
    grep -v "^$" | \
    head -1)

  if [[ -z "$fallback_secret" ]]; then
    return 0  # Couldn't extract, skip check
  fi

  # Check length (must be at least 64 bytes for Plug cookie store)
  if [[ ${#fallback_secret} -lt 64 ]]; then
    echo "ERROR: SECRET_KEY_BASE fallback is only ${#fallback_secret} bytes, but Plug requires 64+." >&2
    echo "Update config/runtime.exs to use a fallback secret that is at least 64 bytes." >&2
    echo "Current fallback: \"$fallback_secret\"" >&2
    exit 1
  fi

  return 0
}

ensure_burrito_zig() {
  local current_version=""
  local uname_s uname_m
  local archive host_triple

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

  if [[ "$uname_s" == "Darwin" ]]; then
    ensure_burrito_zig_on_darwin "$archive" "$host_triple"
    return 0
  fi

  if command -v zig >/dev/null 2>&1; then
    current_version="$(zig version 2>/dev/null || true)"
  fi

  if [[ "$current_version" == "$REQUIRED_ZIG_VERSION" ]]; then
    return 0
  fi

  use_zig_binary "$(download_bundled_zig "$archive" "$host_triple")"
}

main() {
  ensure_burrito_zig

  if [[ "$(uname -s)" == "Darwin" ]] && command -v xcrun >/dev/null 2>&1; then
    export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
  fi

  export MIX_ENV=prod
  export PHX_SERVER=true
  export FOUNDRY_STANDALONE=1
  # Force linker flags to avoid unsupported options from picosat_elixir
  export LDFLAGS="${LDFLAGS:-} -Wl,-undefined,dynamic_lookup"
  export CFLAGS="${CFLAGS:--O2}"

  # Verify runtime config will provide a valid SECRET_KEY_BASE
  # Plug cookie store requires at least 64 bytes
  verify_secret_key_base_config

  mix deps.get

  # Patch picosat_elixir to fix incorrect sys/unistd.h include on Linux
  # This needs to be done both before initial compile and before release for cross-compilation
  apply_picosat_patches() {
    local picosat_c="deps/picosat_elixir/c_src/picosat.c"
    if [[ -f "$picosat_c" ]]; then
      sed -i.bak 's/#include <sys\/unistd\.h>/#include <unistd.h>/' "$picosat_c"
      rm -f "${picosat_c}.bak"
    fi

    local picosat_makefile="deps/picosat_elixir/c_src/Makefile"
    if [[ -f "$picosat_makefile" ]]; then
      sed -i.bak 's/-undefined suppress//' "$picosat_makefile"
      rm -f "${picosat_makefile}.bak"
    fi
  }

  apply_picosat_patches

  npm install --prefix apps/foundry_web/assets
  mix compile
  rm -rf _build/prod/rel
  mix cmd --app foundry_web mix assets.deploy

  # Apply patches again before release in case they got reset
  apply_picosat_patches

  if [[ -n "$TARGET" ]]; then
    BURRITO_TARGET="$TARGET" mix release --overwrite foundry
  else
    mix release --overwrite foundry
  fi

  # CRITICAL: Enable runtime.exs configuration in the release
  # By default, Elixir releases have RUNTIME_CONFIG=false in sys.config,
  # which prevents runtime.exs from being loaded. We need to enable it so
  # FOUNDRY_STANDALONE env var can be read at startup and endpoint config applied.
  local sys_config="_build/prod/rel/foundry/releases/0.1.0/sys.config"
  if [[ -f "$sys_config" ]]; then
    if sed -i.bak 's/RUNTIME_CONFIG=false/RUNTIME_CONFIG=true/' "$sys_config"; then
      echo "✓ Enabled RUNTIME_CONFIG in sys.config"
      rm -f "${sys_config}.bak"
    else
      echo "⚠ Failed to enable RUNTIME_CONFIG in sys.config" >&2
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
