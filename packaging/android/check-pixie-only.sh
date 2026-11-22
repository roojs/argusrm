#!/usr/bin/env bash
# Enforce that Android builds use Pixie packages exclusively and never build or
# substitute third-party libraries from source.
#
# Usage:
#   packaging/android/check-pixie-only.sh prebuild
#   packaging/android/check-pixie-only.sh post-init
#   packaging/android/check-pixie-only.sh post-meson
#   packaging/android/check-pixie-only.sh jnilibs
set -euo pipefail

ARGUS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE="${1:-prebuild}"
PIXIEWOOD_BASE="${OLLMCHAT_PIXIEWOOD:-$ARGUS_ROOT/.pixiewood}"
PIXIEWOOD_ARCH="${PIXIEWOOD_ARCH:-aarch64}"
PIXIEWOOD_BUILD_DIR="$PIXIEWOOD_BASE/bin-$PIXIEWOOD_ARCH"
PIXIEWOOD_PIXIE="${PIXIEWOOD_PIXIE:-$PIXIEWOOD_BASE/pixie}"

fail_illegal() {
  local reason="$1"
  cat >&2 <<EOF
==============================================================================
ILLEGAL CHANGE HAS BEEN DONE — DO NOT BUILD THIS.
Reason: $reason
Report to the user: Pixie packages need updating at source, not here.
Do not compile libocrpc or libocsqlite from source or work around a missing
Pixie drop in this repository.
==============================================================================
EOF
  exit 1
}

cursor_agent=0
if [[ "${CURSOR_AGENT:-}" == "1" ]]; then
	cursor_agent=1
fi

check_static_rules() {
  if [ "${PIXIEWOOD_USE_PIXIE:-}" != "1" ]; then
    fail_illegal "PIXIEWOOD_USE_PIXIE is '${PIXIEWOOD_USE_PIXIE:-unset}' (must be 1; from-source Android dependency builds are forbidden)."
  fi

  gtk_pins="$ARGUS_ROOT/android/pixie-gtk.pins"
  if [ ! -f "$gtk_pins" ] || ! grep -q 'Knowles%2Fgtk' "$gtk_pins"; then
    fail_illegal "android/pixie-gtk.pins must pin the Knowles GTK IME Pixie (run packaging/android/stage-ollmchat-android-pins.sh from pinned OLLMchat)."
  fi

  if grep -qE "subdir\([^)]*libocrpc|subdir\([^)]*libocsqlite" "$ARGUS_ROOT/meson.build"; then
    fail_illegal "meson.build subdir-compiles libocrpc or libocsqlite (forbidden on Android; use Pixie pkg-config)."
  fi

  local meson_file
  for meson_file in \
    "$ARGUS_ROOT/meson.build" \
    "$ARGUS_ROOT/shared/meson.build" \
    "$ARGUS_ROOT/controller/meson.build" \
    "$ARGUS_ROOT/agent/meson.build" \
    "$ARGUS_ROOT/server/meson.build"; do
    if [ -f "$meson_file" ] && grep -Eq '(^|[^[:alnum:]_])subproject[[:space:]]*\(' "$meson_file"; then
      fail_illegal "Found subproject(...) call in ${meson_file#"$ARGUS_ROOT/"}."
    fi
  done

  if [ -d "$ARGUS_ROOT/subprojects" ]; then
    local entry base
    for entry in "$ARGUS_ROOT/subprojects"/*; do
      [ -e "$entry" ] || continue
      base="$(basename "$entry")"
      if [ "$base" = "packagefiles" ]; then
        continue
      fi
      fail_illegal "Unexpected entry in subprojects/: $base (third-party wraps or source checkouts are forbidden)."
    done
  fi
}

check_pixie_ocrpc_packages() {
  local pkg_dir="$PIXIEWOOD_PIXIE/lib/arm64-v8a/pkgconfig"
  local pixie_lib_dir="$PIXIEWOOD_PIXIE/lib/arm64-v8a"

  if [ ! -d "$pkg_dir" ]; then
    fail_illegal "Missing Pixie pkg-config directory: $pkg_dir"
  fi

  local pkg
  for pkg in ocrpc ocsqlite; do
    if ! PKG_CONFIG_PATH="$pkg_dir" pkg-config --exists "$pkg" 2>/dev/null; then
      if [ "$cursor_agent" -eq 1 ]; then
        fail_illegal "Pixie ${pkg}.pc is missing — ask the user to refresh Pixie packages (do not compile dependencies from source)."
      fi
      fail_illegal "Pixie pkg-config missing ${pkg}.pc — update Pixie packages at source."
    fi
  done

  local lib
  for lib in libocrpc.so libocsqlite.so; do
    if [ ! -f "$pixie_lib_dir/$lib" ]; then
      fail_illegal "Pixie sysroot missing $lib ($pixie_lib_dir)."
    fi
  done

}

check_no_from_source_rpc_libs() {
  local ninja_file="$PIXIEWOOD_BUILD_DIR/build.ninja"
  if [ ! -f "$ninja_file" ]; then
    fail_illegal "Missing Meson ninja file: $ninja_file"
  fi

  if grep -qE 'libocrpc/[^ ]+\.vala|libocsqlite/[^ ]+\.vala' "$ninja_file"; then
    fail_illegal "Meson ninja file compiles libocrpc or libocsqlite from Vala source (forbidden on Android)."
  fi

  if [ -d "$PIXIEWOOD_BUILD_DIR/vendor/libocrpc" ] || [ -d "$PIXIEWOOD_BUILD_DIR/vendor/libocsqlite" ]; then
    fail_illegal "Build tree contains from-source libocrpc or libocsqlite artifacts."
  fi
}

check_post_init() {
  check_static_rules

  local pixie_xml="$PIXIEWOOD_BASE/pixiewood-from-pixie.xml"
  if [ ! -f "$pixie_xml" ]; then
    fail_illegal "Missing Pixie-filtered manifest: $pixie_xml"
  fi

  local remaining_deps
  remaining_deps="$(python3 - "$pixie_xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

PW = "https://sp1rit.arpa/pixiewood/"
tree = ET.parse(sys.argv[1])
deps = tree.getroot().find(f"{{{PW}}}dependencies")
if deps is not None:
    names = [child.tag.split("}")[-1] for child in list(deps)]
    if names:
        print(", ".join(names))
PY
)"
  if [ -n "$remaining_deps" ]; then
    fail_illegal "Dependencies not provided by Pixie remain in $pixie_xml: $remaining_deps"
  fi

  check_pixie_ocrpc_packages

  if [ -d "$PIXIEWOOD_BUILD_DIR/subprojects" ] && [ -n "$(ls -A "$PIXIEWOOD_BUILD_DIR/subprojects" 2>/dev/null)" ]; then
    fail_illegal "Meson build directory contains compiled subprojects: $PIXIEWOOD_BUILD_DIR/subprojects"
  fi

  local meson_log="$PIXIEWOOD_BUILD_DIR/meson-logs/meson-log.txt"
  if [ -f "$meson_log" ] && ! grep -q 'pkg-config-wrapper' "$meson_log"; then
    fail_illegal "Meson build directory is not configured against the Pixie pkg-config-wrapper ($meson_log)."
  fi
}

check_jni_libs() {
  check_post_init
  check_no_from_source_rpc_libs

  local jni_dir="$PIXIEWOOD_BASE/android/app/src/main/jniLibs/arm64-v8a"
  local pixie_lib_dir="$PIXIEWOOD_PIXIE/lib/arm64-v8a"

  if [ ! -d "$jni_dir" ]; then
    fail_illegal "Missing Android jniLibs directory: $jni_dir"
  fi
  if [ ! -d "$pixie_lib_dir" ]; then
    fail_illegal "Missing Pixie library directory: $pixie_lib_dir"
  fi

  local so name pixie_so
  for so in "$jni_dir"/*.so; do
    [ -e "$so" ] || continue
    name="$(basename "$so")"
    case "$name" in
      libargus-controller.so)
        continue
        ;;
    esac
    pixie_so="$pixie_lib_dir/$name"
    if [ ! -f "$pixie_so" ]; then
      fail_illegal "Non-Pixie shared library staged in jniLibs: $name"
    fi
    if ! cmp -s "$so" "$pixie_so"; then
      fail_illegal "Shared library $name in jniLibs differs from the Pixie package ($pixie_so)."
    fi
  done
}

case "$PHASE" in
  prebuild)
    check_static_rules
    ;;
  post-init)
    check_post_init
    ;;
  post-meson)
    check_static_rules
    check_pixie_ocrpc_packages
    check_no_from_source_rpc_libs
    ;;
  jnilibs)
    check_jni_libs
    ;;
  *)
    echo "Unknown phase: $PHASE (expected prebuild, post-init, post-meson, or jnilibs)" >&2
    exit 2
    ;;
esac