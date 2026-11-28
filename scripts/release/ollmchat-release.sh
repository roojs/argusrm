#!/usr/bin/env bash
# Resolve the OLLMchat git ref and release tag for CI and Android packaging.
# Default: newest v* tag on GitHub via git ls-remote (no Releases API).
# Override: OLLMCHAT_RELEASE, or packaging/ollmchat.ref for a local branch/tag only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REF_FILE="$ROOT/packaging/ollmchat.ref"
REPO="${OLLMCHAT_REPO:-https://github.com/roojs/OLLMchat.git}"

meson_version() {
	local file="$1"
	awk -F"'" '/^[[:space:]]*version:/ { print $2; exit }' "$file"
}

latest_release_tag() {
	local tag
	tag="$(
		git ls-remote --tags --refs "$REPO" \
			| awk -F/ '/refs\/tags\/v[0-9]/ && $NF !~ /-packages$/ { print $NF }' \
			| sort -V | tail -1
	)"
	if [ -z "$tag" ]; then
		echo "Could not resolve latest OLLMchat tag from $REPO" >&2
		exit 1
	fi
	echo "$tag"
}

resolve_ref() {
	if [ -n "${OLLMCHAT_RELEASE:-}" ]; then
		echo "$OLLMCHAT_RELEASE"
		return
	fi
	if [ -f "$REF_FILE" ]; then
		local from_file
		from_file="$(tr -d '[:space:]' < "$REF_FILE" | sed 's/#.*//')"
		if [ -n "$from_file" ]; then
			echo "$from_file"
			return
		fi
	fi
	latest_release_tag
}

ref="$(resolve_ref)"
if [ -z "$ref" ]; then
	echo "empty OLLMchat ref" >&2
	exit 1
fi

case "${1:-tag}" in
	ref)
		echo "$ref"
		;;
	tag)
		if [[ "$ref" == v* ]]; then
			echo "$ref"
			exit 0
		fi
		root="${OLLMCHAT_ROOT:-${OLLMCHAT_META:-}}"
		if [ -z "$root" ] || [ ! -f "$root/meson.build" ]; then
			echo "Check out OLLMchat at ref=$ref (set OLLMCHAT_ROOT) to map meson version to v-tag" >&2
			exit 1
		fi
		echo "v$(meson_version "$root/meson.build")"
		;;
	*)
		echo "usage: ollmchat-release.sh [ref|tag]" >&2
		exit 1
		;;
esac