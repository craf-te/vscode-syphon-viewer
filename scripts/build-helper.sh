#!/usr/bin/env bash
# Builds syphon-bridge for release into bin/ and fixes up its rpath to match
# the packaged layout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"

"$ROOT/scripts/fetch-syphon-framework.sh"

cd "$ROOT/helper"
swift build -c release --arch arm64
BUILT="$(swift build -c release --arch arm64 --show-bin-path)/syphon-bridge"

mkdir -p "$ROOT/bin"
cp "$BUILT" "$ROOT/bin/syphon-bridge"

# Drop the development absolute rpath, leaving only @executable_path/../Frameworks.
# Package.swift passes Context.packageDirectory + "/../vendor", so the string
# baked in is the unnormalised helper/../vendor form. install_name_tool only
# removes exact matches, so it has to be given in that same form.
DEV_RPATH="$ROOT/helper/../vendor"
install_name_tool -delete_rpath "$DEV_RPATH" "$ROOT/bin/syphon-bridge" 2>/dev/null || true

# Assemble Frameworks/ for packaging.
#
# A framework bundle keeps Headers and Modules as symlinks to directories, and
# vsce's secretlint tries to read them as files and dies with EISDIR. All dyld
# needs is the install name @rpath/Syphon.framework/Versions/A/Syphon, so ship
# a minimal layout with no symlinks and no headers.
FW_DST="$ROOT/Frameworks/Syphon.framework/Versions/A"
rm -rf "$ROOT/Frameworks"
mkdir -p "$FW_DST"
cp "$VENDOR/Syphon.framework/Versions/A/Syphon" "$FW_DST/Syphon"
if [ -d "$VENDOR/Syphon.framework/Versions/A/Resources" ]; then
  mkdir -p "$FW_DST/Resources"
  # Only Info.plist. Nibs and headers are not needed at runtime.
  find "$VENDOR/Syphon.framework/Versions/A/Resources" -maxdepth 1 -type f \
    -name 'Info.plist' -exec cp {} "$FW_DST/Resources/" \;
fi

if find "$ROOT/Frameworks" -type l | grep -q .; then
  echo "error: symlinks remain in the Frameworks to be bundled" >&2
  exit 1
fi

codesign --force --sign - "$FW_DST/Syphon" 2>/dev/null
codesign --force --sign - "$ROOT/bin/syphon-bridge" 2>/dev/null

echo "built: $ROOT/bin/syphon-bridge"
otool -l "$ROOT/bin/syphon-bridge" | grep -A2 LC_RPATH | grep "path " || true
