#!/bin/bash
# Сборка StreamRecord без Xcode-проекта — только swiftc.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/StreamRecord.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "==> Чищу предыдущую сборку"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "==> Компилирую Sources/main.swift"
# Универсальный бинарник: Apple Silicon + Intel (macOS 26 ещё работает на части Intel-маков)
swiftc -O -target arm64-apple-macos11.0 Sources/main.swift -o build/StreamRecord-arm64
swiftc -O -target x86_64-apple-macos11.0 Sources/main.swift -o build/StreamRecord-x86_64
lipo -create build/StreamRecord-arm64 build/StreamRecord-x86_64 -output "$MACOS_DIR/StreamRecord"
rm -f build/StreamRecord-arm64 build/StreamRecord-x86_64

echo "==> Иконка приложения (Tools/AppIcon.png, генератор: Tools/make_icon_bubble.py)"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
    sips -z $sz $sz Tools/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    sips -z $((sz*2)) $((sz*2)) Tools/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"

echo "==> Копирую Info.plist"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Подписываю"
if [ -n "${SIGN_ID:-}" ]; then
    # Релиз: Developer ID + hardened runtime + разрешения на камеру/микрофон (см. release.sh)
    codesign --force --options runtime --timestamp --entitlements StreamRecord.entitlements --sign "$SIGN_ID" "$APP"
else
    codesign --force --deep -s "Apple Development: sinteticdjs@gmail.com (7F6LLUU3ML)" "$APP"
fi

# Снимаем карантин, чтобы Gatekeeper не требовал «Правый клик → Открыть»
# при каждой пересборке. Для локально собранного .app это безопасно.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Готово: $APP"
# Первый запуск через open регистрирует приложение в LaunchServices —
# дальше открывается обычным двойным кликом.
[ -n "${NO_OPEN:-}" ] || open "$APP"
