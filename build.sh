#!/bin/zsh
# Builds MD Viewer.app (+ Quick Look extension), signs it, installs to /Applications and registers it.
#   ./build.sh            build + install
#   ./build.sh --no-install
set -euo pipefail
cd "$(dirname "$0")"

ARCH=$(uname -m)
TARGET="$ARCH-apple-macos13.0"
BUILD=build
APP="$BUILD/MD Viewer.app"
APPEX="$APP/Contents/PlugIns/MDPreview.appex"
INSTALL_DIR=/Applications
# Signing identity: first "Apple Development" cert, else ad-hoc. Override with SIGN_ID=...
SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}
SIGN_ID=${SIGN_ID:--}

echo "→ Cleaning"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

echo "→ Compiling app ($TARGET)"
swiftc -O -module-name MDViewer -target "$TARGET" \
  Sources/Shared/*.swift Sources/App/*.swift \
  -framework Cocoa -framework WebKit \
  -o "$APP/Contents/MacOS/MDViewer"

echo "→ Compiling Quick Look extension"
swiftc -O -module-name MDPreview -parse-as-library -application-extension -target "$TARGET" \
  Sources/Shared/*.swift Sources/Extension/*.swift \
  -framework Cocoa -framework Quartz -framework WebKit \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/Contents/MacOS/MDPreview"

cp Resources/App-Info.plist "$APP/Contents/Info.plist"
cp Resources/Extension-Info.plist "$APPEX/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "→ Icon"
swift Scripts/make-icon.swift "$BUILD/AppIcon.iconset" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signing with: $SIGN_ID"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp=none \
  --entitlements Resources/Extension.entitlements "$APPEX"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

[[ "${1:-}" == "--no-install" ]] && { echo "✓ Built: $APP"; exit 0; }

echo "→ Installing to $INSTALL_DIR"
DEST="$INSTALL_DIR/MD Viewer.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -d "$DEST" ]] && { pluginkit -r "$DEST/Contents/PlugIns/MDPreview.appex" 2>/dev/null || true; rm -rf "$DEST"; }
ditto "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

"$LSREG" -f -R -trusted "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/MDPreview.appex"
pluginkit -e use -i com.ertu.mdviewer.preview
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
killall -q QuickLookUIService 2>/dev/null || true

echo "✓ Installed: $DEST"
pluginkit -m -i com.ertu.mdviewer.preview -v || true
