#!/bin/bash
# Build Save Point.app, install it in /Applications and (re)launch it.
# SAVEPOINT_APP_DIR overrides the install folder; SAVEPOINT_NO_LAUNCH=1 builds without launching.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="${SAVEPOINT_APP_DIR:-/Applications}/Save Point.app"
[ "${SAVEPOINT_NO_LAUNCH:-}" = 1 ] || { pkill -x SavePoint; pkill -x Hearthian; } 2>/dev/null || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/SavePoint "$app/Contents/MacOS/SavePoint"
if [ -f Resources/icon.png ]; then
  set=$(mktemp -d)/SavePoint.iconset
  mkdir -p "$set"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon.png --out "$set/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/icon.png --out "$set/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$set" -o "$app/Contents/Resources/SavePoint.icns"
fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Save Point</string>
  <key>CFBundleDisplayName</key><string>Save Point</string>
  <key>CFBundleIdentifier</key><string>com.alextemina.savepoint</string>
  <key>CFBundleExecutable</key><string>SavePoint</string>
  <key>CFBundleIconFile</key><string>SavePoint</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.6.0</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST
# A stable identity keeps macOS permissions across rebuilds; ad-hoc resets them every build.
identity="${SAVEPOINT_SIGN_IDENTITY:-Hearthian Local Signing}"
if security find-identity -v -p codesigning | grep -q "\"$identity\""; then
  codesign --force --sign "$identity" "$app"
else
  echo "no '$identity' signing identity, signing ad-hoc (permissions reset on every build)" >&2
  codesign --force --sign - "$app"
fi
[ "${SAVEPOINT_NO_LAUNCH:-}" = 1 ] || open "$app"
echo "$app"
