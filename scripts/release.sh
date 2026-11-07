#!/bin/zsh
# Builds a distributable release: universal app, zip, DMG and checksums in ./dist.
# Usage: scripts/release.sh <version> [build-number]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh <version> [build]}"
BUILD="${2:-$(git rev-list --count HEAD)}"
NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)
APP="build/$NAME.app"
DIST="dist"

echo "▶ $NAME $VERSION ($BUILD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist

if [[ "${UNIVERSAL:-1}" == "1" ]]; then scripts/build.sh release --universal; else scripts/build.sh release; fi
lipo -archs "$APP/Contents/MacOS/$NAME" | sed 's/^/   archs: /'
codesign --verify --deep --strict "$APP" && echo "   signature ok (ad-hoc)"

rm -rf "$DIST"; mkdir -p "$DIST"
ZIP="$DIST/$NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

# DMG with an Applications shortcut so users can drag to install.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/$NAME-$VERSION.dmg"
hdiutil create -quiet -volname "$NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

(cd "$DIST" && shasum -a 256 *.zip *.dmg > "SHA256SUMS.txt" && cat SHA256SUMS.txt)
du -h "$DIST"/* | sed 's/^/   /'
echo "✔ $DIST"
