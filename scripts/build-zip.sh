#!/bin/bash
# Packages build/CodexBridger.app as a zipped archive for distribution.
#
# Usage: build-zip.sh [version]
#
# A disk image is the friendlier thing to hand a person, but creating one needs disk
# arbitration access, which is not available in every build environment (containers, CI
# sandboxes). A zip needs neither, so this is the packaging path that works everywhere.
# The version defaults to the contents of VERSION so the file name and the app cannot
# disagree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="CodexBridger"
APP_DIR="build/$APP_NAME.app"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    VERSION="$(tr -d "[:space:]" < VERSION)"
fi

if [[ ! -d "$APP_DIR" ]]; then
    echo "error: $APP_DIR not found; run build-app.sh first" >&2
    exit 1
fi

# The archive must contain the version it is named after, so check the bundle rather than
# trusting the argument.
BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")"
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
    echo "error: the app reports version \"$BUNDLE_VERSION\" but the archive is named for \"$VERSION\"" >&2
    exit 1
fi

ZIP_PATH="build/$APP_NAME-$VERSION.zip"

echo "==> Creating $ZIP_PATH"
rm -f "$ZIP_PATH"
# ditto is the macOS-aware archiver: it preserves the bundle's metadata, extended
# attributes and symlinks, which plain zip does not.
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

# Prove the archive is intact and carries the app, rather than assuming the command worked.
#
# The listing is captured once and then examined. Piping straight into `grep -q` looked
# equivalent but was not: grep exits at the first match, unzip takes SIGPIPE, and `pipefail`
# turns that into a failed pipeline — so a perfectly good archive was reported as broken.
LISTING="$(unzip -l "$ZIP_PATH")"
if ! grep -q "$APP_NAME.app/Contents/MacOS/$APP_NAME" <<< "$LISTING"; then
    echo "error: the archive does not contain the executable" >&2
    exit 1
fi

STAGED="$(grep -c "$APP_NAME.app/" <<< "$LISTING")"
SIZE="$(du -h "$ZIP_PATH" | cut -f1)"
echo "==> Done: $ZIP_PATH ($SIZE, version $VERSION, $STAGED entries)"
