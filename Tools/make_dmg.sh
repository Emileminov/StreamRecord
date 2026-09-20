#!/bin/bash
# Собирает оформленный StreamRecord.dmg: фон, крупные иконки, стрелка, иконка тома.
#
# Почему не create-dmg: его AppleScript-шаг на свежих macOS доносит до .DS_Store
# только границы окна — размер иконок и фон теряются. Здесь тот же приём, но
# настройки проверяются на заново смонтированном образе: если фон не записался,
# скрипт падает, а не отдаёт молча пустой DMG.
set -euo pipefail

cd "$(dirname "$0")/.."

VOL="StreamRecord"
APP="build/$VOL.app"
DMG="build/$VOL.dmg"
TMP="build/dmg-work"

# Окно и позиции иконок. Начало координат — левый верхний угол окна.
WIN_X=200; WIN_Y=120; WIN_W=660; WIN_H=400
ICON_SIZE=128
APP_X=170;  APP_Y=205
LINK_X=490; LINK_Y=205

if [ ! -d "$APP" ]; then
    echo "Нет $APP — сначала ./build.sh" >&2
    exit 1
fi

hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || true
rm -rf "$TMP" "$DMG"
mkdir -p "$TMP/src/.background"

echo "==> Рисую фон окна"
swift Tools/make_dmg_bg.swift "$TMP/bg.png" 1
swift Tools/make_dmg_bg.swift "$TMP/bg@2x.png" 2
# Два разрешения в одном .tiff — чтобы фон был чётким и на Retina.
tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" -out "$TMP/src/.background/bg.tiff" >/dev/null

echo "==> Готовлю содержимое"
cp -R "$APP" "$TMP/src/"
ln -s /Applications "$TMP/src/Applications"
cp "$APP/Contents/Resources/AppIcon.icns" "$TMP/src/.VolumeIcon.icns"

# Образ создаём по размеру содержимого, поэтому все файлы кладём заранее:
# на смонтированном томе мы только проставляем метаданные.
echo "==> Создаю образ"
hdiutil create -srcfolder "$TMP/src" -volname "$VOL" -fs HFS+ \
    -format UDRW -o "$TMP/work.dmg" >/dev/null 2>&1

echo "==> Монтирую"
hdiutil attach "$TMP/work.dmg" >/dev/null 2>&1
sleep 2

# На свежесмонтированном томе первый проход не закрепляется: Finder ещё не
# завёл состояние окна, и настройки вида до .DS_Store не доходят. Поэтому
# сначала вхолостую открываем и закрываем окно.
echo "==> Прогреваю окно"
osascript >/dev/null <<APPLESCRIPT
tell application "Finder" to tell disk "$VOL"
    open
    delay 2
    close
end tell
APPLESCRIPT
sleep 1

# Ошибки AppleScript не глушим: молча пропущенный set — ровно та причина,
# по которой оформление терялось.
echo "==> Оформляю окно"
osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL"
        open
        delay 1
        set w to container window
        set current view of w to icon view
        set toolbar visible of w to false
        set statusbar visible of w to false
        set the bounds of w to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H))}

        set opts to the icon view options of w
        set arrangement of opts to not arranged
        set icon size of opts to $ICON_SIZE
        set text size of opts to 13
        set label position of opts to bottom
        set background picture of opts to file ".background:bg.tiff"

        set position of item "$VOL.app" of w to {$APP_X, $APP_Y}
        set position of item "Applications" of w to {$LINK_X, $LINK_Y}

        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Иконка тома показывается только с этим флагом.
SetFile -a C "/Volumes/$VOL"
sync
sleep 1
hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1
sleep 1

echo "==> Упаковываю"
hdiutil convert "$TMP/work.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null 2>&1

# Проверяем итоговый файл — то, что реально скачает получатель.
# Размер иконок читается через Finder, а вот background picture на macOS 26
# через AppleScript не читается вообще («Сбой обработчика AppleEvent»), поэтому
# наличие фона проверяем по записи в .DS_Store.
echo "==> Проверяю готовый образ"
hdiutil attach "$DMG" >/dev/null 2>&1
sleep 2
BG_REFS=$(strings "/Volumes/$VOL/.DS_Store" | grep -c "bg.tiff" || true)
ICONS=$(osascript <<APPLESCRIPT
tell application "Finder" to tell disk "$VOL"
    open
    delay 1
    set out to (icon size of the icon view options of container window) as string
    close
    return out
end tell
APPLESCRIPT
)
hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1
echo "    размер иконок: $ICONS, ссылок на фон в .DS_Store: $BG_REFS"

if [ "$ICONS" != "$ICON_SIZE" ] || [ "$BG_REFS" -eq 0 ]; then
    echo "Оформление не записалось — проверь образ вручную." >&2
    exit 1
fi

rm -rf "$TMP"

echo "==> Готово: $DMG"
ls -lh "$DMG"
