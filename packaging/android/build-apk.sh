#!/usr/bin/env bash
# Build the Argus APK with OLLMchat's Pixiewood sequence.
# scripts/android/build-pixiewood-apk.sh is copied from OLLMchat at build time.
# This runs the same steps as its run_pixiewood_build, and installs Argus's
# application classes where that function installs OllmApplication.
set -euo pipefail

ARGUS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$ARGUS_ROOT/scripts/android/build-pixiewood-apk.sh"

if [ ! -f "$src" ]; then
  echo "OLLMchat Android build script missing: $src" >&2
  exit 1
fi

export PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ARGUS_ROOT/packaging/android/pixiewood-argus.xml}"

runner="$(mktemp -p "$ARGUS_ROOT/scripts/android" argus-pixiewood-build.XXXXXX.sh)"
trap 'rm -f "$runner"' EXIT

# Keep the helper next to the copied script so its ROOT_DIR is the Argus tree.
# Drop the phase dispatcher; that path installs OLLMchat's chat classes.
sed '/^case "\$PIXIEWOOD_PHASE"/,$d' "$src" > "$runner"
if grep -q '^case "\$PIXIEWOOD_PHASE"' "$runner"; then
  echo "Failed to strip the OLLMchat phase dispatcher from $src" >&2
  exit 1
fi

cat >> "$runner" << 'EOF'
install_argus_java() {
  local dest_dir="$ROOT_DIR/.pixiewood/android/app/src/main/java/org/roojs/argus"
  local app_src="$ROOT_DIR/shared/android/ArgusApplication.java"
  local browse_src="$ROOT_DIR/shared/android/PairBrowse.java"

  if [ ! -f "$app_src" ]; then
    echo "ArgusApplication.java missing: $app_src" >&2
    exit 1
  fi
  if [ ! -f "$browse_src" ]; then
    echo "PairBrowse.java missing: $browse_src" >&2
    exit 1
  fi
  mkdir -p "$dest_dir"
  cp -a "$app_src" "$dest_dir/ArgusApplication.java"
  cp -a "$browse_src" "$dest_dir/PairBrowse.java"
}

patch_argus_manifest() {
  local manifest="$ROOT_DIR/.pixiewood/android/app/src/main/AndroidManifest.xml"

  if [ ! -f "$manifest" ]; then
    echo "AndroidManifest missing: $manifest" >&2
    exit 1
  fi
  sed -i 's/android:name="org.gtk.android.RuntimeApplication"/android:name="org.roojs.argus.ArgusApplication"/' "$manifest"
}

# Same order as OLLMchat run_pixiewood_build. generate's org/gtk/android
# symlink stays. Only jniLibs is copied off its symlink.
run_argus_pixiewood_build() {
  init_pixiewood_env
  maybe_download_meson_subprojects "$MESON_FOR_ANDROID"

  echo "Reconfiguring Pixiewood Meson build."
  maybe_reconfigure_pixiewood_build "$MESON_FOR_ANDROID" "${PIXIEWOOD_CONFIGURE_OPTIONS[@]}"

  rm -rf "$ROOT_DIR/.pixiewood/android/app/src/main/jniLibs"
  sync_pixiewood_ini_manifest
  run_pixiewood generate
  patch_pixiewood_gradle_native_libs
  run_pixiewood build --skip-gradle
  materialize_pixiewood_jni_libs
  install_argus_java
  patch_argus_manifest
  run_pixiewood_gradle_assemble
}

run_argus_pixiewood_build
EOF

bash "$runner"
