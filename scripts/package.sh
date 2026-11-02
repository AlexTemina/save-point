#!/bin/bash
# Build a drag-to-install disk image: dist/SavePoint-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
stage=$(mktemp -d)
SAVEPOINT_APP_DIR="$stage" SAVEPOINT_NO_LAUNCH=1 ./scripts/bundle.sh >/dev/null
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$stage/Save Point.app/Contents/Info.plist")
ln -s /Applications "$stage/Applications"
mkdir -p dist
rm -f "dist/SavePoint-$version.dmg"
hdiutil create -volname "Save Point" -srcfolder "$stage" -ov -format UDZO "dist/SavePoint-$version.dmg" >/dev/null
echo "dist/SavePoint-$version.dmg"
