#!/usr/bin/env bash
#
# Puts Syphon.framework in vendor/.
#
# Background:
#   Syphon's own GitHub Releases stop at tag "5" from 2015: x86_64 only, OpenGL
#   only, no modulemap. Unusable here. The main branch is still maintained and
#   does support Metal and arm64, but the maintainers do not ship binaries and
#   ask people to build from source.
#     https://github.com/Syphon/Syphon-Framework/issues/64
#
#   The author of node-syphon hosts a universal build instead, with the Syphon
#   maintainers' agreement. It is the official repository cloned and built with
#   xcodebuild -arch x86_64 -arch arm64, with no changes to the source.
#     https://github.com/benoitlahoz/node-syphon/blob/main/scripts/build-syphon.sh
#
# By default this fetches that build, pinned by version and checked by hash.
#
# Usage:
#   fetch-syphon-framework.sh                  pinned build (default)
#   fetch-syphon-framework.sh --latest         newest release, no hash check
#   fetch-syphon-framework.sh --build          build from Syphon main (needs Metal Toolchain)
#   fetch-syphon-framework.sh --force          rebuild vendor/
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"

PINNED_TAG="v1.1.5"
PINNED_URL="https://github.com/benoitlahoz/node-syphon/releases/download/${PINNED_TAG}/SyphonFramework.zip"
PINNED_SHA256="9d31b2c4c079ab5d2b9260c155e964eb238cf889620e2eb86c8d9c6aa4e5ff08"
LATEST_URL="https://github.com/benoitlahoz/node-syphon/releases/latest/download/SyphonFramework.zip"
SRC_REPO="https://github.com/Syphon/Syphon-Framework.git"

MODE="pinned"
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --latest) MODE="latest" ;;
    --build)  MODE="build" ;;
    --force)  FORCE=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# What the extension needs: arm64 code, a modulemap so Swift can import it, and
# the Metal client headers. Missing any of these makes the build unusable.
verify() {
  local fw="$1"
  [ -f "$fw/Modules/module.modulemap" ]       || { echo "  no module.modulemap" >&2; return 1; }
  [ -f "$fw/Headers/SyphonMetalClient.h" ]    || { echo "  no SyphonMetalClient.h" >&2; return 1; }
  [ -f "$fw/Versions/A/Syphon" ]              || { echo "  no framework binary" >&2; return 1; }
  lipo -archs "$fw/Versions/A/Syphon" 2>/dev/null | grep -q arm64 \
                                              || { echo "  does not contain arm64" >&2; return 1; }
  return 0
}

if [ -d "$VENDOR/Syphon.framework" ]; then
  if [ "$FORCE" -eq 0 ] && verify "$VENDOR/Syphon.framework"; then
    echo "vendor/Syphon.framework already meets requirements; skipping."
    exit 0
  fi
  rm -rf "$VENDOR/Syphon.framework"
fi

mkdir -p "$VENDOR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

extract_into_vendor() {
  local zip="$1"
  unzip -q "$zip" -d "$TMP/fw"
  local found
  found="$(find "$TMP/fw" -name 'Syphon.framework' -type d | head -1)"
  [ -n "$found" ] || { echo "no Syphon.framework inside the zip" >&2; return 1; }
  cp -R "$found" "$VENDOR/"
}

download_pinned() {
  echo "fetching pinned build: $PINNED_TAG"
  curl -fL --progress-bar "$PINNED_URL" -o "$TMP/fw.zip" || return 1
  local actual
  actual="$(shasum -a 256 "$TMP/fw.zip" | awk '{print $1}')"
  if [ "$actual" != "$PINNED_SHA256" ]; then
    echo "error: SHA256 mismatch" >&2
    echo "  expected: $PINNED_SHA256" >&2
    echo "  actual:   $actual" >&2
    return 1
  fi
  echo "SHA256 verified"
  extract_into_vendor "$TMP/fw.zip"
}

download_latest() {
  echo "fetching the newest release (no hash check)"
  curl -fL --progress-bar "$LATEST_URL" -o "$TMP/fw.zip" || return 1
  extract_into_vendor "$TMP/fw.zip"
}

build_from_source() {
  # Since Xcode 26 the Metal compiler is a separate component. xcrun --find
  # metal can return a path even when the tool is absent, so test it by actually
  # compiling an empty shader.
  if ! echo 'kernel void t() {}' | xcrun metal -x metal -c - -o /dev/null >/dev/null 2>&1; then
    echo "error: Metal Toolchain is not installed. Run:" >&2
    echo "  xcodebuild -downloadComponent MetalToolchain" >&2
    return 1
  fi

  echo "building from Syphon main."
  git clone -q --depth 1 "$SRC_REPO" "$TMP/src"
  ( cd "$TMP/src" && xcodebuild -project Syphon.xcodeproj -target Syphon \
      -configuration Release -arch x86_64 -arch arm64 ONLY_ACTIVE_ARCH=NO \
      CONFIGURATION_BUILD_DIR="$TMP/src/build" build ) >"$TMP/build.log" 2>&1 || {
    echo "build failed. log: $TMP/build.log" >&2
    grep -iE "error: " "$TMP/build.log" | head -5 >&2 || true
    return 1
  }
  [ -d "$TMP/src/build/Syphon.framework" ] || return 1
  cp -R "$TMP/src/build/Syphon.framework" "$VENDOR/"
}

case "$MODE" in
  pinned) download_pinned || { echo "pinned fetch failed; trying the newest release." >&2; download_latest; } ;;
  latest) download_latest ;;
  build)  build_from_source ;;
esac

xattr -dr com.apple.quarantine "$VENDOR/Syphon.framework" 2>/dev/null || true

if ! verify "$VENDOR/Syphon.framework"; then
  echo "error: the installed Syphon.framework does not meet requirements." >&2
  exit 1
fi

echo "installed vendor/Syphon.framework ($(lipo -archs "$VENDOR/Syphon.framework/Versions/A/Syphon"))"
