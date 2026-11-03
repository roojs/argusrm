#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:?tag required}"
OUTPUT="${2:-${ROOT}/release-notes.md}"

"${ROOT}/scripts/release/changelog.sh" release-notes "${TAG}" -o "${OUTPUT}"

tmp="$(mktemp)"
repo="${GITHUB_REPOSITORY:-roojs/argusrm}"
{
	echo "Argus is under development and is not ready for production use."
	echo
	echo "This release contains the AppImage, Windows, and available Android builds for \`${TAG}\`."
	echo
	echo "Debian and RPM files are on [${TAG}-packages](https://github.com/${repo}/releases/tag/${TAG}-packages)."
	echo
	echo "---"
	echo
	cat "${OUTPUT}"
} > "${tmp}"
mv "${tmp}" "${OUTPUT}"
