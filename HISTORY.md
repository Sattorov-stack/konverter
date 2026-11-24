# HISTORY — Konverter

## 2026-11-24 23:40
- Просили: выяснить, почему приложение стало требовать LibreOffice, хотя раньше работало.
- Сделано: диагностика без изменения кода. LibreOffice на Маке отсутствует; по логу `~/Library/Logs/Konverter.log` ошибки 20:27–20:29 относятся к попытке PDF → DOCX. Встроенный macOS-fallback (`NativeDoc.swift`) поддерживает PDF → TXT, но не PDF → DOCX.
- Проверено: `/Applications/LibreOffice.app` и `soffice` отсутствуют, cask не установлен; три записи об ошибке в логе; чтение `Converter.swift`, `NativeDoc.swift`, `Formats.swift`.
- Важно: не менять `Formats.swift`, `Converter.swift`, `NativeDoc.swift` без отдельной просьбы. Для PDF → DOCX нужен LibreOffice (`brew install --cask libreoffice`) или отдельное решение о приблизительном fallback. Подробности — в Obsidian `Приложения/Konverter и NotchApp — диагностика 2026-11-24.md`.
