#!/bin/bash
# Собирает Konverter.app. Запуск: ./build.sh
set -e
cd "$(dirname "$0")"
APP="Konverter.app"

echo "→ Компилирую Swift…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Konverter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Konverter"
cp Info.plist "$APP/Contents/Info.plist"

echo "→ Кладу ffmpeg внутрь приложения (для работы без интернета)…"
FF="$APP/Contents/Resources/ffmpeg"
if [ "$(uname -m)" = "arm64" ]; then P="darwin-arm64"; else P="darwin-x64"; fi
URL="https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-$P"
if curl -fsSL "$URL.gz" -o /tmp/konv-ffmpeg.gz 2>/dev/null; then
  gunzip -c /tmp/konv-ffmpeg.gz > "$FF"; chmod +x "$FF"; rm -f /tmp/konv-ffmpeg.gz
elif curl -fsSL "$URL" -o "$FF" 2>/dev/null; then
  chmod +x "$FF"
fi
if [ -f "$FF" ] && "$FF" -version >/dev/null 2>&1; then
  echo "   ffmpeg встроен"
else
  rm -f "$FF"
  echo "   Не удалось скачать ffmpeg. Выполни: brew install ffmpeg (приложение найдёт его само)"
fi

echo "→ Кладу ИИ-модуль для увеличения (Real-ESRGAN, около 50 МБ)…"
RE="$APP/Contents/Resources/realesrgan"
TMPZ="/tmp/konv-resr"
rm -rf "$TMPZ" "$TMPZ.zip"
if curl -fsSL -o "$TMPZ.zip" "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip" \
   && unzip -q -o "$TMPZ.zip" -d "$TMPZ" && [ -f "$TMPZ/realesrgan-ncnn-vulkan" ]; then
  mkdir -p "$RE"
  cp "$TMPZ/realesrgan-ncnn-vulkan" "$RE/"
  cp -R "$TMPZ/models" "$RE/"
  chmod +x "$RE/realesrgan-ncnn-vulkan"
  xattr -dr com.apple.quarantine "$RE" 2>/dev/null || true
  echo "   ИИ-модуль встроен"
else
  echo "   Не удалось скачать ИИ-модуль: пункт «ИИ-увеличение» работать не будет, остальное работает."
fi
rm -rf "$TMPZ" "$TMPZ.zip"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo ""
echo "Готово: $(pwd)/$APP"
echo "Перенести в «Программы»:  mv \"$APP\" /Applications/"
