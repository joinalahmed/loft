#!/bin/zsh
# Builds Loft.app into ./build. Usage: scripts/build.sh [debug|release] [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
UNIVERSAL="${2:-}"
APP="build/Loft.app"
ARCH_FLAGS=()
PRODUCT_DIR=".build/$CONFIG"
if [[ "$UNIVERSAL" == "--universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
echo "▶ swift build -c $CONFIG ${ARCH_FLAGS[*]:-}"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" 2>&1 | grep -vE '^\[|^Compiling|^Build complete|^Emitting|^Linking|^Write ' || true
BIN="$PRODUCT_DIR/Loft"
[[ -x "$BIN" ]] || { echo "build failed: $BIN missing"; exit 1; }
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Loft"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Vendor/mediaremote-adapter/MediaRemoteAdapter.framework "$APP/Contents/Frameworks/"
cp Vendor/mediaremote-adapter/mediaremote-adapter.pl "$APP/Contents/Resources/"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"
# Local builds are signed with a fixed self-signed identity when one is installed, so macOS sees
# the same app on every rebuild (keychain "Always Allow" and privacy grants stick). Releases, and
# machines without the identity, use an ad-hoc signature. LOFT_ADHOC=1 forces ad-hoc.
IDENTITY="-"
if [[ "${LOFT_ADHOC:-0}" != "1" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"Loft Local Signing"'; then
  IDENTITY="Loft Local Signing"
fi
codesign --force --deep --sign "$IDENTITY" --identifier dev.joinal.loft "$APP" 2>&1 | grep -v 'replacing existing signature' || true
codesign --verify --deep --strict "$APP" 2>/dev/null || { echo "signing with '$IDENTITY' failed; falling back to ad-hoc"; codesign --force --deep --sign - --identifier dev.joinal.loft "$APP"; IDENTITY="-"; }
echo "   signed: $([[ "$IDENTITY" == "-" ]] && echo ad-hoc || echo "$IDENTITY")"
echo "✔ $APP"
