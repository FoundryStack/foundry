#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="${FOUNDRY_DESKTOP_REPO_ROOT:-$(cd "${DESKTOP_ROOT}/../.." && pwd)}"
BINARIES_DIR="${FOUNDRY_DESKTOP_BINARIES_DIR:-${DESKTOP_ROOT}/src-tauri/binaries}"
BURRITO_OUT_DIR="${FOUNDRY_DESKTOP_BURRITO_OUT_DIR:-${REPO_ROOT}/burrito_out}"
HOST_TRIPLE="${FOUNDRY_DESKTOP_HOST_TRIPLE:-$(rustc -vV | sed -n 's/^host: //p')}"
SIDECAR_DEST="${BINARIES_DIR}/foundry-sidecar-${HOST_TRIPLE}"

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
    exit 1
  fi

  sidecar_type="$(file -b "${sidecar_path}")"

  if [[ "${sidecar_type}" == *"shell script"* || "${sidecar_type}" == *"text executable"* ]]; then
    echo "Prepared sidecar is not standalone: ${sidecar_type}" >&2
    exit 1
  fi

  if grep -q "mix foundry.studio" "${sidecar_path}" 2>/dev/null; then
    echo "Prepared sidecar still references mix foundry.studio and is not standalone." >&2
    exit 1
  fi

  if grep -q "MIX_BUILD_PATH" "${sidecar_path}" 2>/dev/null; then
    echo "Prepared sidecar still depends on MIX_BUILD_PATH and is not standalone." >&2
    exit 1
  fi
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
  local sidecar_source

  sidecar_source="$(
    find "${BURRITO_OUT_DIR}" -maxdepth 1 -type f -perm -111 | sort | tail -n 1
  )"

  if [[ -z "${sidecar_source}" ]]; then
    echo "No Burrito executable was produced in ${BURRITO_OUT_DIR}" >&2
    exit 1
  fi

  cp "${sidecar_source}" "${SIDECAR_DEST}"
  chmod +x "${SIDECAR_DEST}"
  verify_standalone_sidecar "${SIDECAR_DEST}"
  echo "Prepared Burrito sidecar at ${SIDECAR_DEST}"
}

if [[ "${FOUNDRY_DESKTOP_FORCE_MIX_FALLBACK:-0}" == "1" ]]; then
  create_mix_wrapper
else
  if [[ "${FOUNDRY_DESKTOP_SKIP_BURRITO_BUILD:-0}" != "1" ]]; then
    ./scripts/release/build_burrito.sh "${BURRITO_TARGET}"
  fi

  copy_burrito_sidecar
fi
