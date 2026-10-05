#!/bin/bash
# Релиз: сборка + подпись Developer ID + нотаризация САМОГО приложения (+ штамп),
# затем оформленный DMG из проштампованного приложения (тоже нотаризован и проштампован).
# Профиль нотаризации (один раз): xcrun notarytool store-credentials launchpad-notary --team-id 4AR298V292
set -euo pipefail
cd "$(dirname "$0")"

export SIGN_ID="${SIGN_ID:-Developer ID Application: Emil EMINOV (4AR298V292)}"
export NO_OPEN=1
PROFILE="${NOTARY_PROFILE:-launchpad-notary}"
APP="build/StreamRecord.app"
DMG="build/StreamRecord.dmg"

./build.sh

echo "==> Нотаризую приложение (обычно 1-5 минут)"
rm -f build/app.zip
ditto -c -k --keepParent "$APP" build/app.zip
xcrun notarytool submit build/app.zip --keychain-profile "$PROFILE" --wait
rm -f build/app.zip
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Собираю оформленный DMG из проштампованного приложения"
./Tools/make_dmg.sh

echo "==> Подписываю и нотаризую DMG"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> Проверка"
spctl --assess --type execute -v "$APP"
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "Готово: $(pwd)/$DMG"
