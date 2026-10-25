#!/bin/zsh
# Merakit "Hachi.app" tanpa Xcode: build release, susun bundle, tanda tangan ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Hachi.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Hachi"

if [[ ! -f Resources/AppIcon.icns || Resources/AppIcon.png -nt Resources/AppIcon.icns ]]; then
    rm -rf build/AppIcon.iconset
    swift scripts/make-icon.swift Resources/AppIcon.png build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hachi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

codesign --force --sign - --identifier com.linggaept.Hachi "$APP"
echo "Selesai: $APP"
