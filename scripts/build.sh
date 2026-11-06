#!/bin/zsh
# Builds Isla.app into ./build. Usage: scripts/build.sh [debug|release] [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
UNIVERSAL="${2:-}"
APP="build/Isla.app"
ARCH_FLAGS=()
PRODUCT_DIR=".build/$CONFIG"
if [[ "$UNIVERSAL" == "--universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  PRODUCT_DIR=".build/apple/Products/$(tr '[:lower:]' '[:upper:]' <<< ${CONFIG:0:1})${CONFIG:1}"
fi
echo "▶ swift build -c $CONFIG ${ARCH_FLAGS[*]:-}"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" 2>&1 | grep -vE '^\[|^Compiling|^Build complete|^Emitting|^Linking|^Write ' || true
BIN="$PRODUCT_DIR/Isla"
[[ -x "$BIN" ]] || { echo "build failed: $BIN missing"; exit 1; }
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Isla"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Vendor/mediaremote-adapter/MediaRemoteAdapter.framework "$APP/Contents/Frameworks/"
cp Vendor/mediaremote-adapter/mediaremote-adapter.pl "$APP/Contents/Resources/"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - --identifier dev.joinal.isla "$APP" 2>&1 | grep -v 'replacing existing signature' || true
echo "✔ $APP"
