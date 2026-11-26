#!/usr/bin/env bash
# Download the published Android libraries and activate them for Pixiewood.
# The GTK + FreeRDP stack comes from the pixiewood-pkgs GitHub Pages pin lists.
# android/pixie-gtk.pins lists Knowles/gtk at track latest;
# scripts/android/resolve-pixie-gtk-pins.sh expands it before merge.
# ocrpc and ocsqlite come from OLLMchat's <tag>-packages GitHub release.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIXIEWOOD_BASE="${OLLMCHAT_PIXIEWOOD:-$ROOT_DIR/.pixiewood}"
DEST="${PIXIEWOOD_PIXIE:-$PIXIEWOOD_BASE/pixie}"
CLONE="$PIXIEWOOD_BASE/pixie-pkg"
RELEASE_URL="${PIXIE_RELEASE_PINS_URL:-https://roojs.github.io/pixiewood-pkgs/release.pins}"
SNAPSHOT_URL="${PIXIE_SNAPSHOT_PINS_URL:-https://roojs.github.io/pixiewood-pkgs/snapshot.pins}"
OLLMCHAT_RELEASE_TAG="${OLLMCHAT_RELEASE:-}"
GTK_TEMPLATE="$ROOT_DIR/android/pixie-gtk.pins"
PINS_STAMP="$DEST/share/pixiewood/pixie.pins"
PKG_DIR="$DEST/lib/arm64-v8a/pkgconfig"

if ! command -v jq >/dev/null 2>&1; then
  echo "fetch-pixie-deps needs jq" >&2
  exit 1
fi

if [ -d "$DEST" ] && [ ! -f "$DEST/share/pixiewood/pixie.cross" ]; then
  rm -rf "$DEST"
fi

if [ ! -f "$GTK_TEMPLATE" ]; then
  echo "GTK pixie pin missing: $GTK_TEMPLATE" >&2
  exit 1
fi

if [ -z "$OLLMCHAT_RELEASE_TAG" ]; then
  OLLMCHAT_RELEASE_TAG="$(curl -fsSL --retry 3 --retry-delay 2 https://api.github.com/repos/roojs/OLLMchat/releases/latest | jq -r .tag_name)"
fi
if [ -z "$OLLMCHAT_RELEASE_TAG" ] || [ "$OLLMCHAT_RELEASE_TAG" = null ]; then
  echo "Could not resolve latest OLLMchat release tag" >&2
  exit 1
fi
OLLMCHAT_VERSION="${OLLMCHAT_RELEASE_TAG#v}"
OLLMCHAT_BASE_URL="https://github.com/roojs/OLLMchat/releases/download/${OLLMCHAT_RELEASE_TAG}-packages"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 --retry-delay 2 "$RELEASE_URL" -o "$work/release.pins"
curl -fsSL --retry 3 --retry-delay 2 "$SNAPSHOT_URL" -o "$work/snapshot.pins"
jq -n \
  --arg tag "$OLLMCHAT_RELEASE_TAG" \
  --arg ver "$OLLMCHAT_VERSION" \
  --arg base "$OLLMCHAT_BASE_URL" '
  {
    packages: [
      {
        abi: "arm64-v8a",
        repo: "https://github.com/roojs/OLLMchat.git",
        name: "ocsqlite",
        track: $ver,
        resolved: $tag,
        inputs: $tag,
        url: ($base + "/ocsqlite-arm-v31-" + $ver + ".pixie")
      },
      {
        abi: "arm64-v8a",
        repo: "https://github.com/roojs/OLLMchat.git",
        name: "ocrpc",
        track: $ver,
        resolved: $tag,
        inputs: $tag,
        url: ($base + "/ocrpc-arm-v31-" + $ver + ".pixie")
      }
    ]
  }
' > "$work/ollmchat.pins"
"$ROOT_DIR/scripts/android/resolve-pixie-gtk-pins.sh" > "$work/gtk.pins"
jq -s '
  ([.[0].packages[] | select(.abi == "arm64-v8a")]) as $rel
  | ([.[1].packages[] | select(.abi == "arm64-v8a")]) as $snap
  | ([.[2].packages[] | select(.abi == "arm64-v8a")]) as $gtk
  | ([.[3].packages[] | select(.abi == "arm64-v8a" and (.name == "ocrpc" or .name == "ocsqlite"))]) as $ollm
  | ($rel + [ $snap[] | select(.name as $n | [$rel[].name] | index($n) | not) ]) as $base
  | [
      $base[]
      | . as $row
      | ([$gtk[] | select(.name == $row.name)] | .[0]) // $row
    ] as $merged
  | {
      packages: (
        $merged + [
          $ollm[]
          | select(.name as $n | [$merged[].name] | index($n) | not)
        ]
      )
    }
' "$work/release.pins" "$work/snapshot.pins" "$work/gtk.pins" "$work/ollmchat.pins" > "$work/merged.pins"

for req in ocrpc ocsqlite freerdp; do
  if ! jq -e --arg name "$req" '[.packages[] | select(.name == $name)] | length > 0' "$work/merged.pins" >/dev/null; then
    echo "Required Pixie package '$req' is missing from merged pins" >&2
    exit 1
  fi
done

# Reuse the sysroot only when the published pin list is the one already
# unpacked. A new glib, freerdp, ocrpc, or ocsqlite in pins must replace it.
if [ -f "$DEST/share/pixiewood/pixie.cross" ] &&
   [ -f "$DEST/share/pixiewood/gtk-android-java/org/gtk/android/ImContext.java" ] &&
   [ -f "$PKG_DIR/ocrpc.pc" ] &&
   [ -f "$PKG_DIR/ocsqlite.pc" ] &&
   [ -f "$PKG_DIR/freerdp3.pc" ] &&
   [ -f "$PKG_DIR/freerdp-client3.pc" ] &&
   [ -f "$PKG_DIR/winpr3.pc" ] &&
   [ -f "$PINS_STAMP" ] &&
   cmp -s "$PINS_STAMP" "$work/merged.pins" &&
   [ "${PIXIEWOOD_REFRESH_SUBPROJECTS:-}" != 1 ]; then
  printf '%s\n' "$DEST"
  exit 0
fi

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
fi

if [ ! -x "$CLONE/scripts/pixie-pkg" ]; then
  rm -rf "$CLONE"
  git clone --depth 1 https://github.com/roojs/pixie-pkg.git "$CLONE"
else
  git -C "$CLONE" pull --ff-only >&2
fi

mkdir -p "$(dirname "$DEST")"
"$CLONE/scripts/pixie-pkg" fetch --dest "$DEST" --pins "$work/merged.pins" --abi arm64-v8a >&2
if [ ! -f "$DEST/share/pixiewood/pixie.cross" ]; then
  echo "Pixie sysroot was not activated: $DEST" >&2
  exit 1
fi
if [ ! -f "$DEST/share/pixiewood/gtk-android-java/org/gtk/android/ImContext.java" ]; then
  echo "Pixie GTK is missing the IME Java glue: $DEST" >&2
  exit 1
fi
for pc in ocrpc.pc ocsqlite.pc freerdp3.pc freerdp-client3.pc winpr3.pc; do
  if [ ! -f "$PKG_DIR/$pc" ]; then
    echo "Pixie sysroot is missing $pc: $PKG_DIR/$pc" >&2
    exit 1
  fi
done
cp "$work/merged.pins" "$PINS_STAMP"
printf '%s\n' "$DEST"
