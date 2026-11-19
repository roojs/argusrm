#!/usr/bin/env bash
# Package the Argus executable. Dependent DLLs are copied from the
# MSYS prefix (the installed OLLMchat release packages). This script
# does not build those packages, and the Windows build must not either.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

build_dir="${BUILD_DIR:-build-windows}"
stage="${ROOT}/dist-windows/Argus"
out_dir="${ROOT}/dist-windows"
version="$(scripts/release/changelog.sh packaging-version)"
out_name="ArgusAgent-${version}-Setup.exe"
out_path="${out_dir}/${out_name}"
if [[ -f "${out_path}" ]]; then
	echo "${out_name} already exists." >&2
	echo "Bump the first version in CHANGELOG.md and meson.build, reconfigure, rebuild argus-agent.exe, then package again." >&2
	exit 1
fi
exe="${build_dir}/agent/argus-agent.exe"
icon="${ROOT}/packaging/windows/argusrm.ico"

[[ -f "${exe}" ]] || {
	echo "missing ${exe}" >&2
	exit 1
}
meson_version="$(awk -F"'" '/^[[:space:]]*version:[[:space:]]*'\''/ { print $2; exit }' meson.build)"
[[ -n "${meson_version}" ]] || {
	echo "meson.build has no project version" >&2
	exit 1
}
built="$(grep -a -o -E 'Argus Remote Management Agent [0-9]+\.[0-9]+\.[0-9]+' "${exe}" | awk '{print $NF}' | sort -u || true)"
[[ -n "${built}" ]] || {
	echo "argus-agent.exe has no compiled version string" >&2
	exit 1
}
mismatch=0
if [[ "${meson_version}" != "${version}" ]]; then
	echo "meson.build is ${meson_version}, but CHANGELOG.md is ${version}." >&2
	mismatch=1
fi
if [[ "${built}" != "${version}" ]]; then
	echo "argus-agent.exe was compiled as ${built}, but CHANGELOG.md is ${version}." >&2
	mismatch=1
fi
if [[ "${mismatch}" -ne 0 ]]; then
	echo "The agent window shows the compiled version. Refusing to package." >&2
	exit 1
fi
[[ -f "${icon}" ]] || {
	echo "missing ${icon}" >&2
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

win_icon="$(cygpath -aw "${icon}")"

makensis \
	-DINST_SRC="$(cygpath -aw "${stage}")" \
	-DPRODUCT_VERSION="${version}" \
	-DOUTFILE="$(cygpath -aw "${out_dir}/${out_name}")" \
	-DMUI_ICON="${win_icon}" \
	-DMUI_UNICON="${win_icon}" \
	packaging/windows/argusrm-agent.nsi

ls -lh "${out_dir}/${out_name}"
