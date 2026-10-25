#!/bin/zsh
# Build lalu buat zip untuk GitHub Releases. Versi diambil dari Resources/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ZIP="build/Hachi-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent build/Hachi.app "$ZIP"
shasum -a 256 "$ZIP"
echo "Siap diunggah: $ZIP (tag v$VERSION)"
