#!/usr/bin/env bash
# Verify CHANGELOG.md, create an annotated version tag, and push it.
# The human runs this script; agents must not create releases.
set -euo pipefail

if [[ "${CURSOR_AGENT:-}" == "1" ]]; then
	echo "error: scripts/release.sh must be run by a human" >&2
	exit 1
fi

retry=0
case "${1:-}" in
	"") ;;
	--retry) retry=1 ;;
	-h|--help)
		echo "Usage: scripts/release.sh [--retry]"
		exit 0
		;;
	*)
		echo "error: unknown option: $1" >&2
		exit 1
		;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

version="$(scripts/release/changelog.sh version)"
project_version="$(awk -F"'" '/^[[:space:]]*version:/ { print $2; exit }' meson.build)"
tag="v${version}"
package_tag="${tag}-packages"

[[ "${version}" == "${project_version}" ]] || {
	echo "error: CHANGELOG.md version ${version} != meson.build ${project_version}" >&2
	exit 1
}

notes="$(scripts/release/changelog.sh notes)"
[[ -n "${notes//[[:space:]]/}" ]] || {
	echo "error: ${version} has no release notes" >&2
	exit 1
}

if [[ -n "$(git status --porcelain)" ]]; then
	echo "error: working tree is not clean; commit or stash first" >&2
	git status --short >&2
	exit 1
fi

git fetch --tags origin

if ((retry)); then
	for old_tag in "${tag}" "${package_tag}"; do
		if git rev-parse -q --verify "refs/tags/${old_tag}" >/dev/null; then
			git tag -d "${old_tag}"
		fi
		if git ls-remote --exit-code --tags origin "refs/tags/${old_tag}" >/dev/null 2>&1; then
			git push origin --delete "${old_tag}"
		fi
	done
fi

for existing_tag in "${tag}" "${package_tag}"; do
	if git rev-parse -q --verify "refs/tags/${existing_tag}" >/dev/null ||
		git ls-remote --exit-code --tags origin "refs/tags/${existing_tag}" >/dev/null 2>&1; then
		echo "error: ${existing_tag} already exists; use --retry after a failed release" >&2
		exit 1
	fi
done

echo "Release ${tag}"
echo "----------------"
printf '%s\n' "${notes}"
echo "----------------"

git tag -a "${tag}" -m "${tag}"
git tag -a "${package_tag}" -m "${package_tag}"
branch="$(git branch --show-current)"
git push -u origin "${branch}"
git push origin "${tag}" "${package_tag}"

echo "Pushed ${tag}. The GitHub mirror will start the release workflow."
