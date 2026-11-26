#!/usr/bin/env bash
# Copy Pixiewood pin files from the pinned OLLMchat tree (GTK IME branch .pixie,
# webkit pins, wraps). Same inputs as OLLMchat's fetch-pixie-deps.
set -euo pipefail

ARGUS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OLLM_ROOT="${OLLMCHAT_ANDROID_ROOT:-$ARGUS_ROOT/../OLLMchat}"

if [ ! -d "$OLLM_ROOT/android" ]; then
  cat >&2 <<EOF
OLLMchat android/ missing: $OLLM_ROOT/android
Set OLLMCHAT_ANDROID_ROOT to a checkout at the latest OLLMchat release (or match CI)
so pixie-gtk.pins pulls the GTK IME Pixie build.
EOF
  exit 1
fi

for name in pixie-gtk.pins pixie-webkit.pins pixiewood-extra.cross; do
  if [ ! -f "$OLLM_ROOT/android/$name" ]; then
    echo "OLLMchat android/$name missing" >&2
    exit 1
  fi
  cp -a "$OLLM_ROOT/android/$name" "$ARGUS_ROOT/android/$name"
done

if [ -d "$OLLM_ROOT/android/pixiewood-wraps" ]; then
  rm -rf "$ARGUS_ROOT/android/pixiewood-wraps"
  cp -a "$OLLM_ROOT/android/pixiewood-wraps" "$ARGUS_ROOT/android/pixiewood-wraps"
fi

if ! grep -qE 'Knowles(/|%2F)gtk' "$ARGUS_ROOT/android/pixie-gtk.pins"; then
  echo "android/pixie-gtk.pins does not reference the Knowles GTK IME Pixie (expected like OLLMchat)" >&2
  exit 1
fi

if [ ! -f "$OLLM_ROOT/vapi/gioopenssl.vapi" ]; then
  echo "OLLMchat vapi/gioopenssl.vapi missing (valac --pkg gioopenssl for Android)" >&2
  exit 1
fi
mkdir -p "$ARGUS_ROOT/android/vapi"
cp -a "$OLLM_ROOT/vapi/gioopenssl.vapi" "$ARGUS_ROOT/android/vapi/gioopenssl.vapi"