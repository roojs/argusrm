#!/usr/bin/env bash
set -euo pipefail

exe="${1:?executable required}"
out="${2:?output directory required}"
mkdir -p "${out}"

if [[ "$(cd "$(dirname "${exe}")" && pwd -P)" != "$(cd "${out}" && pwd -P)" ]]; then
	cp -f "${exe}" "${out}/"
fi

copy_dependency()
{
	local path="$1"
	local name
	name="$(basename "${path}")"
	[[ -f "${out}/${name}" ]] && return
	if [[ -f "${path}" ]]; then
		cp -f "${path}" "${out}/${name}"
	elif [[ -f "${MSYSTEM_PREFIX:-/ucrt64}/bin/${name}" ]]; then
		cp -f "${MSYSTEM_PREFIX:-/ucrt64}/bin/${name}" "${out}/${name}"
	fi
}

scan()
{
	local target="$1"
	local line name path
	while IFS= read -r line; do
		case "${line}" in
			*" not found"*)
				name="$(awk '{ print $1 }' <<< "${line}")"
				copy_dependency "${MSYSTEM_PREFIX:-/ucrt64}/bin/${name}"
				;;
			*"=> "*)
				path="$(awk -F'=> ' '{ print $2 }' <<< "${line}" | awk '{ print $1 }')"
				path="${path//\\//}"
				if [[ "${path}" == */ucrt64/bin/* || "${path}" == */mingw64/bin/* ]]; then
					copy_dependency "${path}"
				fi
				;;
		esac
	done < <(ldd "${target}" 2>&1 || true)
}

scan "${exe}"
for _ in 1 2 3 4 5 6; do
	before="$(find "${out}" -maxdepth 1 -name '*.dll' | wc -l)"
	while IFS= read -r -d '' dll; do
		scan "${dll}"
	done < <(find "${out}" -maxdepth 1 -name '*.dll' -print0)
	after="$(find "${out}" -maxdepth 1 -name '*.dll' | wc -l)"
	[[ "${before}" -eq "${after}" ]] && break
done
