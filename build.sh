#!/bin/bash
# Сборка Заметочки.app. Нужны только Command Line Tools (xcode-select --install).
#
#   ./build.sh          собрать build/Zametki.app
#   ./build.sh run      собрать и запустить отсюда (для разработки)
#   ./build.sh install  собрать, положить в ~/Applications и запустить
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Zametki.app"

if [ ! -f build/icon-out/Assets.car ]; then
    echo "==> иконка"
    mkdir -p build/icon-out
    swift tools/make-icon.swift
    xcrun actool build/AppIcon.icon --compile build/icon-out --platform macosx \
        --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist build/icon-out/partial.plist >/dev/null
fi

echo "==> swift build"
swift build -c release --product Zametki
BIN="$(swift build -c release --show-bin-path)/Zametki"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Zametki"
strip -x "$APP/Contents/MacOS/Zametki"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/icon-out/AppIcon.icns build/icon-out/Assets.car Resources/Caveat.ttf Resources/OFL.txt "$APP/Contents/Resources/"
SIGN_ID="-"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Local Dev Signing" && SIGN_ID="Local Dev Signing"
codesign --force --sign "$SIGN_ID" "$APP"
echo "==> готово: $APP"

case "${1:-}" in
run)
    pkill -x Zametki 2>/dev/null && sleep 0.5 || true
    open "$APP"
    ;;
install)
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    pkill -x Zametki 2>/dev/null && sleep 0.5 || true
    rm -rf "$DEST/Zametki.app"
    cp -R "$APP" "$DEST/"
    echo "==> установлено: $DEST/Zametki.app"
    open "$DEST/Zametki.app"
    ;;
esac
