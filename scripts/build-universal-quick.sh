#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# build-universal-quick.sh — Быстрая сборка UNIVERSAL .app БЕЗ тестов.
#
# Собирает release для x86_64 и arm64 параллельно-инкрементально,
# склеивает lipo, собирает myCoder.app, подписывает и (по желанию)
# перезапускает приложение.
#
# Использование:
#   ./scripts/build-universal-quick.sh            # только собрать
#   ./scripts/build-universal-quick.sh --relaunch # собрать + перезапустить
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="myCoder"
APP_BUNDLE="myCoder.app"
RELAUNCH=0

for arg in "$@"; do
    case "$arg" in
        --relaunch) RELAUNCH=1 ;;
        *) echo "Неизвестный аргумент: $arg"; exit 2 ;;
    esac
done

echo "━━━ [1/5] Сборка x86_64 (release, без тестов)…"
swift build -c release --product "$APP_NAME" \
    --triple x86_64-apple-macosx \
    --jobs 8 --disable-sandbox \
    -Xswiftc -no-whole-module-optimization -Xswiftc -Onone

echo "━━━ [2/5] Сборка arm64 (release, без тестов)…"
swift build -c release --product "$APP_NAME" \
    --triple arm64-apple-macosx \
    --jobs 8 --disable-sandbox \
    -Xswiftc -no-whole-module-optimization -Xswiftc -Onone

echo "━━━ [3/5] Склейка universal (lipo)…"
lipo -create \
    .build/x86_64-apple-macosx/release/$APP_NAME \
    .build/arm64-apple-macosx/release/$APP_NAME \
    -output .build/release/$APP_NAME-universal

echo "━━━ [4/5] Сборка бандла $APP_BUNDLE…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp .build/release/$APP_NAME-universal "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp myCoder/Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
if [ -f myCoder/Resources/AppIcon.icns ]; then
    cp myCoder/Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
fi
shopt -s nullglob
for b in .build/release/*.bundle; do
    cp -R "$b" "$APP_BUNDLE/Contents/Resources/"
done
shopt -u nullglob

echo "━━━ [5/5] Подпись…"
IDENT="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development:/{print $2; exit}')"
if [ -z "$IDENT" ]; then
    IDENT="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application:/{print $2; exit}')"
fi
if [ -z "$IDENT" ]; then
    IDENT="-"
fi
codesign --force --deep --sign "$IDENT" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "━━━ ✅ Готово: $APP_BUNDLE"
echo "━━━    Архитектуры: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | tr '\n' ' ')"

if [ "$RELAUNCH" -eq 1 ]; then
    echo "━━━ Перезапуск приложения…"
    pkill -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    sleep 1
    open "$APP_BUNDLE"
    echo "━━━ ✅ Запущено."
fi
