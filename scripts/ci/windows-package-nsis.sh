#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

build_dir="${BUILD_DIR:-build-windows}"
stage="${ROOT}/dist-windows/Argus"
out_dir="${ROOT}/dist-windows"
version="$(scripts/release/changelog.sh packaging-version)"
out_name="ArgusAgent-${version}-Setup.exe"
exe="${build_dir}/agent/argus-agent.exe"

[[ -f "${exe}" ]] || {
	echo "missing ${exe}" >&2
	exit 1
}
command -v makensis >/dev/null || {
	echo "NSIS is not installed" >&2
	exit 1
}

rm -rf "${stage}"
mkdir -p "${stage}" "${out_dir}"
cp -f "${exe}" "${stage}/argus-agent.exe"
cp -f "${exe}" "${stage}/argus-tray.exe"
objcopy --subsystem windows "${stage}/argus-tray.exe"

scripts/ci/copy-windows-runtime.sh "${stage}/argus-agent.exe" "${stage}"

makensis \
	-DINST_SRC="$(cygpath -aw "${stage}")" \
	-DPRODUCT_VERSION="${version}" \
	-DOUTFILE="$(cygpath -aw "${out_dir}/${out_name}")" \
	packaging/windows/argusrm-agent.nsi

ls -lh "${out_dir}/${out_name}"
