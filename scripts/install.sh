#!/bin/zsh
# Build, pasang ke /Applications, lalu jalankan ulang.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

TARGET="/Applications/Hachi.app"
# Hentikan versi yang sedang jalan (berdasarkan bundle id, bukan pola nama proses).
osascript -e 'tell application id "com.linggaept.Hachi" to quit' 2>/dev/null || true
sleep 1
rm -rf "$TARGET"
cp -R "build/Hachi.app" "$TARGET"
open "$TARGET"
echo "Terpasang di $TARGET"
