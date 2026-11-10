#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:?tag required}"
OUTPUT="${2:-${ROOT}/release-notes.md}"

"${ROOT}/scripts/release/changelog.sh" release-notes "${TAG}" -o "${OUTPUT}"

tmp="$(mktemp)"
{
	echo "Argus is under development and is not ready for production use."
	echo
	echo "This release contains the Debian packages, Fedora RPMs, Windows installer, and Android APK for \`${TAG}\`."
	echo
	echo "---"
	echo
	cat "${OUTPUT}"
} > "${tmp}"
mv "${tmp}" "${OUTPUT}"
