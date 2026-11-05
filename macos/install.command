#!/bin/bash
# Собирает приложение и ставит его в «Программы»
cd "$(dirname "$0")"
xattr -dr com.apple.quarantine . 2>/dev/null
pkill -x Konverter 2>/dev/null
chmod +x build.sh
if ! ./build.sh; then
  echo ""
  echo "Сборка не удалась. Пришли текст ошибки выше."
  read -p "Нажми Enter, чтобы закрыть"
  exit 1
fi
rm -rf /Applications/Konverter.app
mv Konverter.app /Applications/
open /Applications/Konverter.app
echo ""
echo "Готово: Конвертер установлен в «Программы»."
