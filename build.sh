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
swiftc -O Sources/main.swift -o "$MACOS_DIR/StreamRecord"

echo "==> Генерирую иконку приложения"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift Tools/make_icon.swift "$ICONSET"
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
