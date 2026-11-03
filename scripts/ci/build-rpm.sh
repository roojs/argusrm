#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
	version="${GITHUB_REF_NAME#v}"
	changelog_version="$(scripts/release/changelog.sh version)"
	[[ "${version}" == "${changelog_version}" ]] || {
		echo "CHANGELOG.md ${changelog_version} != tag ${version}" >&2
		exit 1
	}
else
	version="$(scripts/release/changelog.sh packaging-version)"
fi
rpm_version="${version//-/\~}"

install -d -m 0755 /etc/pki/rpm-gpg
curl -fsSL https://roojs.github.io/repos/key.gpg \
	-o /etc/pki/rpm-gpg/RPM-GPG-KEY-roojs
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-roojs
curl -fsSL https://roojs.github.io/repos/repo \
	-o /etc/yum.repos.d/roojs.repo

dnf -y install --setopt=install_weak_deps=False \
	rpm-build meson ninja-build gcc vala systemd-rpm-macros \
	libocrpc-devel libocsqlite-devel \
	'pkgconfig(glib-2.0)' 'pkgconfig(gio-unix-2.0)' \
	'pkgconfig(gee-0.8)' 'pkgconfig(json-glib-1.0)' \
	'pkgconfig(libsoup-3.0)' 'pkgconfig(gnutls)' \
	'pkgconfig(sqlite3)' 'pkgconfig(gtk4)' \
	'pkgconfig(libadwaita-1)' 'pkgconfig(avahi-gobject)'

topdir="${ROOT}/.rpmbuild"
rm -rf "$topdir" "${ROOT}/artifacts"
mkdir -p "$topdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} \
	"${ROOT}/artifacts"

tar \
	--exclude='./.git' \
	--exclude='./.rpmbuild' \
	--exclude='./artifacts' \
	--exclude='./build*' \
	--transform "s|^\\./|argusrm-${rpm_version}/|" \
	-czf "${topdir}/SOURCES/argusrm-${rpm_version}.tar.gz" .

cp packaging/rpm/argusrm.spec "${topdir}/SPECS/argusrm.spec"
scripts/release/changelog.sh sync \
	--release "v${version}" \
	--splice-spec "${topdir}/SPECS/argusrm.spec"
rpmbuild -bb \
	--define "_topdir ${topdir}" \
	--define "argusrm_version ${rpm_version}" \
	"${topdir}/SPECS/argusrm.spec"

find "${topdir}/RPMS" -type f -name '*.rpm' \
	! -name '*debuginfo*' ! -name '*debugsource*' \
	-exec cp -v {} "${ROOT}/artifacts/" \;
ls -lh "${ROOT}/artifacts"
