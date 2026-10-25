#!/bin/bash
# Compile NPpp et produit dist/NPpp.app. Option : ./build.sh install  (copie dans ~/Applications)
set -euo pipefail
cd "$(dirname "$0")"
BUILD="$HOME/Library/Caches/NPpp-build"   # hors Dropbox
swift build -c release --scratch-path "$BUILD"

[ -f Resources/AppIcon.icns ] || swift tools/make_icon.swift Resources || true

APP="dist/NPpp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/release/NPpp" "$APP/Contents/MacOS/NPpp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✓ $APP"

if [ "${1:-}" = "install" ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/NPpp.app"
    cp -R "$APP" "$HOME/Applications/"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/NPpp.app" || true
    echo "✓ installé dans ~/Applications/NPpp.app"
fi
