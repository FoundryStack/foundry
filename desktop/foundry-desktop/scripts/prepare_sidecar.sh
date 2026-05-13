#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DESKTOP_ROOT}/../.." && pwd)"
BINARIES_DIR="${DESKTOP_ROOT}/src-tauri/binaries"
HOST_TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
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
cd "${REPO_ROOT}"
exec "${mix_bin}" foundry.studio "\$@"
EOF

  chmod +x "${SIDECAR_DEST}"
  echo "Prepared fallback mix sidecar at ${SIDECAR_DEST}"
}

if [[ "${FOUNDRY_DESKTOP_FORCE_MIX_FALLBACK:-0}" == "1" ]]; then
  create_mix_wrapper
elif ./scripts/release/build_burrito.sh "${BURRITO_TARGET}"; then
  SIDECAR_SOURCE="$(find "${REPO_ROOT}/burrito_out" -maxdepth 1 -type f | sort | tail -n 1)"

  if [[ -z "${SIDECAR_SOURCE}" ]]; then
    echo "No Burrito output was produced in ${REPO_ROOT}/burrito_out" >&2
    exit 1
  fi

  cp "${SIDECAR_SOURCE}" "${SIDECAR_DEST}"
  chmod +x "${SIDECAR_DEST}"
  echo "Prepared Burrito sidecar at ${SIDECAR_DEST}"
else
  create_mix_wrapper
fi
