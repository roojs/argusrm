#!/usr/bin/env bash
# Enforce that Android builds use Pixie packages exclusively and never build or
# substitute third-party libraries from source.
#
# Usage:
#   packaging/android/check-pixie-only.sh prebuild
#   packaging/android/check-pixie-only.sh post-init
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
==============================================================================
EOF
  exit 1
}

check_static_rules() {
  if [ "${PIXIEWOOD_USE_PIXIE:-}" != "1" ]; then
    fail_illegal "PIXIEWOOD_USE_PIXIE is '${PIXIEWOOD_USE_PIXIE:-unset}' (must be 1; from-source Android dependency builds are forbidden)."
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
      libargus-controller.so|libocrpc.so|libocsqlite.so)
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
  jnilibs)
    check_jni_libs
    ;;
  *)
    echo "Unknown phase: $PHASE (expected prebuild, post-init, or jnilibs)" >&2
    exit 2
    ;;
esac
