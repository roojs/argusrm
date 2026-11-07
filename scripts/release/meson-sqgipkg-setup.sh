#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:?build directory required}"
export PKG_CONFIG_SYSROOT_DIR="${SQGI_LINUX_SYSROOT:?SQGI_LINUX_SYSROOT is not set}"
export PKG_CONFIG_LIBDIR="${SQGI_LINUX_SYSROOT}/usr/lib/${SQGI_LINUX_TRIPLET}/pkgconfig:${SQGI_LINUX_SYSROOT}/usr/share/pkgconfig"

args=(
	--prefix=/usr
	--sysconfdir=/etc
	--localstatedir=/var
	--buildtype=release
	-Ddocs=false
)
if [[ -n "${SQGI_LINUX_MESON_CROSS_FILE:-}" ]]; then
	args+=(--cross-file "${SQGI_LINUX_MESON_CROSS_FILE}")
fi

if [[ -f "${BUILD_DIR}/build.ninja" ]]; then
	meson setup "${BUILD_DIR}" --reconfigure "${args[@]}"
else
	meson setup "${BUILD_DIR}" "${args[@]}"
fi
