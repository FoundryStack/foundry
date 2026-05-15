#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="${FOUNDRY_DESKTOP_REPO_ROOT:-$(cd "${DESKTOP_ROOT}/../.." && pwd)}"
BINARIES_DIR="${FOUNDRY_DESKTOP_BINARIES_DIR:-${DESKTOP_ROOT}/src-tauri/binaries}"
BURRITO_OUT_DIR="${FOUNDRY_DESKTOP_BURRITO_OUT_DIR:-${REPO_ROOT}/burrito_out}"
HOST_TRIPLE="${FOUNDRY_DESKTOP_HOST_TRIPLE:-$(rustc -vV | sed -n 's/^host: //p')}"
SIDECAR_DEST="${BINARIES_DIR}/foundry-sidecar"

case "${HOST_TRIPLE}" in
  aarch64-apple-darwin)
    BURRITO_TARGET="macos_silicon"
    ;;
  x86_64-apple-darwin)
    BURRITO_TARGET="macos"
    ;;
  x86_64-unknown-linux-gnu)
    BURRITO_TARGET="linux"
    ;;
  *)
    echo "Unsupported host triple for Foundry sidecar build: ${HOST_TRIPLE}" >&2
    exit 1
    ;;
esac

mkdir -p "${BINARIES_DIR}"

cd "${REPO_ROOT}"

verify_standalone_sidecar() {
  local sidecar_path="$1"
  local sidecar_type

  if [[ ! -f "${sidecar_path}" ]]; then
    echo "Expected standalone sidecar at ${sidecar_path}, but the file does not exist." >&2
    return 1
  fi

  sidecar_type="$(file -b "${sidecar_path}")"

  if [[ "${sidecar_type}" == *"shell script"* || "${sidecar_type}" == *"text executable"* ]]; then
    echo "Prepared sidecar is not standalone: ${sidecar_type}" >&2
    return 1
  fi

  if grep -qa "mix foundry.studio" "${sidecar_path}" 2>/dev/null; then
    echo "Prepared sidecar still references mix foundry.studio and is not standalone." >&2
    return 1
  fi

  if grep -qa "MIX_BUILD_PATH" "${sidecar_path}" 2>/dev/null; then
    echo "Prepared sidecar still depends on MIX_BUILD_PATH and is not standalone." >&2
    return 1
  fi
}

sidecar_is_stale() {
  local sidecar_path="$1"
  local sidecar_mtime latest_source_mtime

  if [[ ! -f "${sidecar_path}" ]]; then
    return 0  # Stale if it doesn't exist
  fi

  sidecar_mtime=$(stat -f%m "${sidecar_path}" 2>/dev/null || stat -c%Y "${sidecar_path}" 2>/dev/null || echo 0)

  # Find the most recent modification time in the source code (excluding build artifacts)
  latest_source_mtime=$(find "${REPO_ROOT}/apps" -path "*/_build" -prune -o -type f \( -name "*.ex" -o -name "*.exs" -o -name "*.eex" -o -name "*.heex" \) -print0 | xargs -0 stat -f%m 2>/dev/null | sort -rn | head -1 || echo 0)

  if [[ ${latest_source_mtime} -gt ${sidecar_mtime} ]]; then
    return 0  # Stale - source code is newer
  fi

  return 1  # Not stale
}

reuse_existing_sidecar_if_available() {
  if [[ ! -f "${SIDECAR_DEST}" ]]; then
    return 1
  fi

  if sidecar_is_stale "${SIDECAR_DEST}"; then
    echo "Sidecar is stale (source code has been modified since build)"
    return 1
  fi

  verify_standalone_sidecar "${SIDECAR_DEST}"
  echo "Reusing existing standalone sidecar at ${SIDECAR_DEST}"
  return 0
}

create_mix_wrapper() {
  local mix_bin
  mix_bin="$(command -v mix || true)"

  if [[ -z "${mix_bin}" ]]; then
    echo "Burrito build failed and no mix executable was found for fallback." >&2
    exit 1
  fi

  cat > "${SIDECAR_DEST}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/opt/homebrew/opt/erlang/bin:\$PATH"
export MIX_BUILD_PATH="\${FOUNDRY_DESKTOP_MIX_BUILD_PATH:-${REPO_ROOT}/_build/foundry_desktop_sidecar}"
cd "${REPO_ROOT}"
exec "${mix_bin}" foundry.studio "\$@"
EOF

  chmod +x "${SIDECAR_DEST}"
  echo "Prepared fallback mix sidecar at ${SIDECAR_DEST}"
}

copy_burrito_sidecar() {
  local sidecar_source=""
  local candidate
  local expected_candidates=(
    "${BURRITO_OUT_DIR}/foundry_${BURRITO_TARGET}"
    "${BURRITO_OUT_DIR}/foundry-${BURRITO_TARGET}"
    "${BURRITO_OUT_DIR}/foundry"
  )

  for candidate in "${expected_candidates[@]}"; do
    if [[ -f "${candidate}" && -x "${candidate}" ]]; then
      sidecar_source="${candidate}"
      break
    fi
  done

  if [[ -z "${sidecar_source}" ]]; then
    while IFS= read -r candidate; do
      if [[ -f "${candidate}" && -x "${candidate}" ]]; then
        sidecar_source="${candidate}"
        break
      fi
    done < <(find "${BURRITO_OUT_DIR}" -maxdepth 1 -type f | sort)
  fi

  if [[ -z "${sidecar_source}" ]]; then
    echo "No Burrito executable was produced in ${BURRITO_OUT_DIR}" >&2
    exit 1
  fi

  trap 'rm -f "${SIDECAR_DEST}"' ERR
  cp "${sidecar_source}" "${SIDECAR_DEST}"
  chmod +x "${SIDECAR_DEST}"
  verify_standalone_sidecar "${SIDECAR_DEST}"
  trap - ERR
  echo "Prepared Burrito sidecar at ${SIDECAR_DEST}"
}

if [[ -z "${HOST_TRIPLE}" ]]; then
  echo "Could not determine host triple: is rustc on PATH?" >&2
  exit 1
fi

if [[ "${FOUNDRY_DESKTOP_FORCE_REBUILD:-0}" != "1" ]] && reuse_existing_sidecar_if_available; then
  exit 0
fi

if [[ "${FOUNDRY_DESKTOP_FORCE_MIX_FALLBACK:-0}" == "1" ]]; then
  create_mix_wrapper
else
  if [[ "${FOUNDRY_DESKTOP_SKIP_BURRITO_BUILD:-0}" != "1" ]]; then
    "${REPO_ROOT}/scripts/release/build_burrito.sh" "${BURRITO_TARGET}"
  fi

  copy_burrito_sidecar
fi
