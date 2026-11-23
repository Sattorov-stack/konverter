#!/bin/bash
# Запуск проекта: ./run.sh [start|stop|restart|status|open|log|fg]  (или командой p <имя>)
P_DIR="$(cd "$(dirname "$0")" && pwd)"
P_NAME=konverter; P_DESC="Konverter (конвертер файлов)"; P_APP=Konverter; P_APP_PATH=/Applications/Konverter.app; P_APP_BUILD="cd macos && ./build.sh && mv Konverter.app /Applications/"
source "$HOME/Projects/_инструменты/launcher/lib.sh"
lib_main "$@"
