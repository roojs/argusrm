#!/usr/bin/env bash
# CHANGELOG.md is the single source of truth for package versions and notes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHANGELOG="${ROOT}/CHANGELOG.md"
DEBIAN_CHANGELOG="${ROOT}/debian/changelog"
MAINTAINER='Alan Knowles <alan@roojs.com>'

die()
{
	echo "error: $*" >&2
	exit 1
}

first_heading()
{
	awk '/^## \[[^]]+\]( - (Unreleased|[0-9]{4}-[0-9]{2}-[0-9]{2}))?$/ {
		print
		exit
	}' "${CHANGELOG}"
}

heading_version()
{
	sed -E 's/^## \[([^]]+)\].*/\1/'
}

first_version()
{
	local heading
	heading="$(first_heading)"
	[[ -n "${heading}" ]] || die "CHANGELOG.md has no version heading"
	printf '%s\n' "${heading}" | heading_version
}

first_body()
{
	awk '
		/^## \[[^]]+\]/ {
			if (seen) {
				exit
			}
			seen = 1
			next
		}
		seen { print }
	' "${CHANGELOG}" | awk '
		{ line[++n] = $0 }
		END {
			first = 1
			last = n
			while (first <= last && line[first] ~ /^[[:space:]]*$/) first++
			while (last >= first && line[last] ~ /^[[:space:]]*$/) last--
			for (i = first; i <= last; i++) print line[i]
		}
	'
}

bullets()
{
	first_body | awk '
		function trim(s) {
			sub(/^[ \t]+/, "", s)
			sub(/[ \t]+$/, "", s)
			return s
		}
		{
			text = trim($0)
			if (text ~ /^[-*] /) {
				if (item != "") print item
				item = substr(text, 3)
			} else if (item != "" && $0 ~ /^[ \t]+/) {
				item = item " " text
			}
		}
		END {
			if (item != "") print item
		}
	'
}

release_version()
{
	local version
	version="$(first_version)"
	[[ "${version}" != "Unreleased" ]] ||
		die "set the first heading to ## [X.Y.Z] - Unreleased"
	first_heading | grep -q ' - Unreleased$' ||
		die "first changelog section is already released"
	printf '%s\n' "${version}"
}

write_debian()
{
	local tag="${1:-}"
	local version
	if [[ -n "${tag}" ]]; then
		version="${tag#v}"
	else
		version="$(first_version)"
	fi
	version="${version//-/\~}-1"

	{
		printf 'argusrm (%s) unstable; urgency=medium\n\n' "${version}"
		if ! bullets | while IFS= read -r item; do
			printf '  * %s\n' "${item}"
		done; then
			exit 1
		fi
		printf '\n -- %s  %s\n' "${MAINTAINER}" \
			"$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
	} > "${DEBIAN_CHANGELOG}"
}

rpm_changelog()
{
	local version="$1"
	printf '%%changelog\n'
	printf '* %s %s - %s-1\n' \
		"$(date -u '+%a %b %d %Y')" "${MAINTAINER}" "${version//-/\~}"
	bullets | while IFS= read -r item; do
		printf -- '- %s\n' "${item}"
	done
}

splice_spec()
{
	local spec="$1"
	local version="$2"
	local tmp
	[[ -f "${spec}" ]] || die "spec not found: ${spec}"
	tmp="$(mktemp)"
	awk '/^%changelog/ { exit } { print }' "${spec}" > "${tmp}"
	rpm_changelog "${version}" >> "${tmp}"
	mv "${tmp}" "${spec}"
}

sync_changelogs()
{
	local tag=""
	local spec=""
	while (($#)); do
		case "$1" in
			--release)
				[[ $# -ge 2 ]] || die "--release requires a tag"
				tag="$2"
				shift 2
				;;
			--splice-spec)
				[[ $# -ge 2 ]] || die "--splice-spec requires a path"
				spec="$2"
				shift 2
				;;
			*)
				die "unknown sync argument: $1"
				;;
		esac
	done

	local version
	version="${tag#v}"
	[[ -n "${version}" ]] || version="$(first_version)"
	write_debian "${tag}"
	if [[ -n "${spec}" ]]; then
		splice_spec "${spec}" "${version}"
	fi
}

finalize()
{
	local tag="$1"
	local version="${tag#v}"
	local current
	current="$(release_version)"
	[[ "${current}" == "${version}" ]] ||
		die "tag ${tag} does not match changelog ${current}"

	write_debian "${tag}"

	local tmp
	tmp="$(mktemp)"
	awk -v version="${version}" -v today="$(date -u '+%Y-%m-%d')" '
		BEGIN { changed = 0 }
		$0 == "## [" version "] - Unreleased" {
			print "## [Unreleased]"
			print ""
			print "## [" version "] - " today
			changed = 1
			next
		}
		{ print }
		END {
			if (!changed) exit 1
		}
	' "${CHANGELOG}" > "${tmp}" ||
		die "could not finalize ${version}"
	mv "${tmp}" "${CHANGELOG}"
}

usage()
{
	cat <<'EOF'
Usage: changelog.sh COMMAND

Commands:
  version
  packaging-version
  notes
  sync [--release TAG] [--splice-spec SPEC]
  release-notes TAG [-o FILE]
  finalize TAG
EOF
}

command="${1:-}"
case "${command}" in
	version)
		release_version
		;;
	packaging-version)
		first_version
		;;
	notes)
		first_body
		;;
	sync)
		shift
		sync_changelogs "$@"
		;;
	release-notes)
		[[ $# -ge 2 ]] || die "release-notes requires a tag"
		tag="$2"
		shift 2
		output="${ROOT}/release-notes.md"
		if [[ "${1:-}" == "-o" || "${1:-}" == "--output" ]]; then
			[[ $# -ge 2 ]] || die "-o requires a path"
			output="$2"
		fi
		[[ "${tag#v}" == "$(first_version)" ]] ||
			die "tag ${tag} does not match the first changelog section"
		first_body > "${output}"
		;;
	finalize)
		[[ $# -eq 2 ]] || die "finalize requires a tag"
		finalize "$2"
		;;
	-h|--help)
		usage
		;;
	*)
		usage >&2
		exit 1
		;;
esac
