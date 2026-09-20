#!/bin/bash
# Собирает оформленный StreamRecord.dmg через create-dmg (brew install create-dmg).
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/StreamRecord.app"
DMG="build/StreamRecord.dmg"
TMP="build/dmg-work"

if [ ! -d "$APP" ]; then
    echo "Нет $APP — сначала ./build.sh" >&2
    exit 1
fi

rm -rf "$TMP" "$DMG"
mkdir -p "$TMP/src"
cp -R "$APP" "$TMP/src/"

echo "==> Рисую фон окна"
swift Tools/make_dmg_bg.swift "$TMP/bg.png" 1
swift Tools/make_dmg_bg.swift "$TMP/bg@2x.png" 2
# Два разрешения в одном .tiff — чтобы фон был чётким и на Retina.
tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" -out "$TMP/bg.tiff" >/dev/null

echo "==> Собираю DMG"
create-dmg \
    --volname "StreamRecord" \
    --volicon "$APP/Contents/Resources/AppIcon.icns" \
    --background "$TMP/bg.tiff" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "StreamRecord.app" 170 205 \
    --hide-extension "StreamRecord.app" \
    --app-drop-link 490 205 \
    --no-internet-enable \
    "$DMG" "$TMP/src"

rm -rf "$TMP"

echo "==> Готово: $DMG"
ls -lh "$DMG"
