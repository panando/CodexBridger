#!/bin/bash
# Builds CodexBridger.app from the Swift package.
#
# SwiftPM is invoked with --disable-sandbox and workspace-local caches so the build
# works in restricted environments where the default clang module cache or the
# nested sandbox is not writable.
#
# Usage: build-app.sh [release|debug] [universal] [dmg]
#
# `universal` adds the Intel slice so the app also runs on Macs that are not Apple
# silicon. The packaging is otherwise identical, and the result is distributed as one
# app bundle containing both architectures.
#
# `dmg` additionally packages the finished app as a disk image for distribution.
#
# The marketing version comes from the VERSION file at the repository root, which is the
# single place it is written down. It is stamped into the bundle's Info.plist here, because
# the About screen reads the version out of the running bundle rather than a constant.
set -euo pipefail

CONFIG="${1:-release}"
FLAVOUR="${2:-native}"
PACKAGE="${3:-app}"
APP_NAME="CodexBridger"
APP_DIR="build/$APP_NAME.app"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The version has one home. A missing or malformed file stops the build rather than
# producing a bundle that reports the wrong version or fails Apple's validation later:
# CFBundleShortVersionString must be one to three period-separated integers.
VERSION_FILE="VERSION"
if [[ ! -f "$VERSION_FILE" ]]; then
    echo "error: $VERSION_FILE not found at the repository root" >&2
    exit 1
fi
VERSION="$(tr -d "[:space:]" < "$VERSION_FILE")"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "error: $VERSION_FILE contains \"$VERSION\", which is not a version Apple accepts" >&2
    echo "       expected one to three period-separated integers, for example 1.0.0" >&2
    exit 1
fi
# The build number is separate from the marketing version and may be supplied by CI.
BUILD_NUMBER="${BUILD_NUMBER:-1}"

ARCH_ARGS=()
SCRATCH=".build"
if [[ "$FLAVOUR" == "universal" ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
    SCRATCH=".build-universal"
fi
# macOS ships bash 3.2, where "${ARCH_ARGS[@]}" on an empty array trips `set -u` with
# "unbound variable" — which broke the plain native build, the command the README tells
# people to run. Every use of the array therefore has to carry the ${VAR[@]+...} guard
# rather than being copied into another array, because a copy is empty in the same way.

export CLANG_MODULE_CACHE_PATH="$ROOT/$SCRATCH/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/$SCRATCH/swiftpm-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

echo "==> Building $CONFIG ($FLAVOUR)"
swift build -c "$CONFIG" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --scratch-path "$SCRATCH" --cache-path "$SCRATCH/cache" --disable-sandbox

BIN="$(swift build -c "$CONFIG" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --scratch-path "$SCRATCH" --cache-path "$SCRATCH/cache" --disable-sandbox --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
    echo "executable not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "support/Info.plist" "$APP_DIR/Contents/Info.plist"
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Stamp the version into the bundle. plutil edits in place and fails loudly on a missing key,
# so a silent mismatch between VERSION and the shipped bundle is not possible.
echo "==> Version $VERSION (build $BUILD_NUMBER)"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
STAMPED="$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")"
if [[ "$STAMPED" != "$VERSION" ]]; then
    echo "error: the bundle reports version \"$STAMPED\" but VERSION says \"$VERSION\"" >&2
    exit 1
fi

# The application icon. CFBundleIconFile in Info.plist names it without the extension, so the
# file has to be called CodexBridger.icns inside Contents/Resources.
ICON="CodexBridger.icns"
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$APP_DIR/Contents/Resources/$ICON"
else
    echo "warning: $ICON not found; the app will use the generic icon" >&2
fi

# Swift runtime compatibility libraries, if the toolchain relocated them.
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
XCODE_SWIFT_RPATH=$(otool -l "$APP_DIR/Contents/MacOS/$APP_NAME" | awk '/path \/Applications\/Xcode\.app\/Contents\/Developer\/Toolchains\/XcodeDefault\.xctoolchain\/usr\/lib\/swift-[^ ]*\/macosx/ { print $2; exit }')
if [[ -n "${XCODE_SWIFT_RPATH:-}" ]]; then
    mkdir -p "$FRAMEWORKS_DIR"
    if [[ -f "$XCODE_SWIFT_RPATH/libswiftCompatibilitySpan.dylib" ]]; then
        cp "$XCODE_SWIFT_RPATH/libswiftCompatibilitySpan.dylib" "$FRAMEWORKS_DIR/"
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$APP_NAME"
    fi
    install_name_tool -delete_rpath "$XCODE_SWIFT_RPATH" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
fi

codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
echo "==> Done: $APP_DIR"

case "$PACKAGE" in
    dmg) "$ROOT/scripts/build-dmg.sh" "$VERSION" ;;
    zip) "$ROOT/scripts/build-zip.sh" "$VERSION" ;;
    app) ;;
    *)
        echo "error: unknown packaging mode \"$PACKAGE\" (expected app, dmg or zip)" >&2
        exit 1
        ;;
esac
