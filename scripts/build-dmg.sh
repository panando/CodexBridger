#!/bin/bash
# Packages build/CodexBridger.app as a distributable disk image.
#
# Usage: build-dmg.sh [version]
#
# The image contains the app and a symlink to /Applications, which is the layout users
# expect: they open the image, drag the app across, and eject. The version defaults to the
# contents of VERSION so the file name and the app cannot disagree.
#
# Why this does not use the obvious command
# ----------------------------------------
# `hdiutil create -srcfolder` is the usual way to build a .dmg, and it needs to mount a
# writable scratch image to copy the files in. Plenty of build environments (containers,
# CI sandboxes) refuse disk arbitration, and there the command fails with a bare
# "operation not permitted" — no amount of retrying helps.
#
# `hdiutil makehybrid` writes the filesystem directly instead of mounting a writable
# image, so it works where `create -srcfolder` does not. The result is compressed with
# `hdiutil convert`. Both steps were verified here by attaching the finished image and
# reading the app back out of it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="CodexBridger"
APP_DIR="build/$APP_NAME.app"
VOLUME_NAME="$APP_NAME"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    VERSION="$(tr -d "[:space:]" < VERSION)"
fi

if [[ ! -d "$APP_DIR" ]]; then
    echo "error: $APP_DIR not found; run build-app.sh first" >&2
    exit 1
fi

# The app inside the image must report the version the image is named after. Reading the
# bundle is the only check that proves the stamping reached the shipped copy.
BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")"
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
    echo "error: the app reports version \"$BUNDLE_VERSION\" but the image is named for \"$VERSION\"" >&2
    exit 1
fi

DMG_PATH="build/$APP_NAME-$VERSION.dmg"
STAGING="build/dmg-staging"
PLAIN_DMG="build/dmg-uncompressed.dmg"
MOUNT_POINT="build/dmg-verify"

echo "==> Staging the disk image contents"
rm -rf "$STAGING" "$DMG_PATH" "$PLAIN_DMG" "$MOUNT_POINT"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Building the filesystem image"
# makehybrid writes the filesystem directly and never attaches a writable image, which is
# what lets this work where `create -srcfolder` cannot.
hdiutil makehybrid -hfs -hfs-volume-name "$VOLUME_NAME" -ov -o "$PLAIN_DMG" "$STAGING" > /dev/null

echo "==> Compressing"
hdiutil convert "$PLAIN_DMG" -format UDZO -ov -o "$DMG_PATH" > /dev/null

rm -f "$PLAIN_DMG"
rm -rf "$STAGING"

# Verify by opening the finished image and reading the app out of it. Building something
# and never opening it is how a release ships an image nobody can mount.
echo "==> Verifying the image"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT" > /dev/null
cleanup() {
    hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ! -x "$MOUNT_POINT/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]]; then
    echo "error: the mounted image does not contain a runnable $APP_NAME.app" >&2
    exit 1
fi
if [[ ! -L "$MOUNT_POINT/Applications" ]]; then
    echo "error: the mounted image has no Applications shortcut to drag the app onto" >&2
    exit 1
fi
MOUNTED_VERSION="$(plutil -extract CFBundleShortVersionString raw "$MOUNT_POINT/$APP_NAME.app/Contents/Info.plist")"
if [[ "$MOUNTED_VERSION" != "$VERSION" ]]; then
    echo "error: the app inside the image reports \"$MOUNTED_VERSION\", expected \"$VERSION\"" >&2
    exit 1
fi
ARCHS="$(lipo -archs "$MOUNT_POINT/$APP_NAME.app/Contents/MacOS/$APP_NAME")"

cleanup
trap - EXIT
rmdir "$MOUNT_POINT" 2>/dev/null || true

# An ad-hoc signature, so the image itself is not notarised either. Signing it keeps the
# usual tools from complaining about an unsigned disk image.
codesign --force --sign - "$DMG_PATH" 2>/dev/null || true

SIZE="$(du -h "$DMG_PATH" | cut -f1)"
echo "==> Done: $DMG_PATH"
echo "    version $VERSION, architectures: $ARCHS, size $SIZE"
