# Konverter

**Бесплатный офлайн-конвертер файлов с «колесом форматов» для macOS и Windows.**

Начните перетаскивать файл, зажмите клавишу, и вокруг курсора появится колесо: бросьте файл на нужный сегмент. Результат появится рядом с оригиналом. Всё работает без интернета.

![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Platform](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6?logo=windows)
![Swift](https://img.shields.io/badge/SwiftUI-F05138?logo=swift&logoColor=white)
![Electron](https://img.shields.io/badge/Electron-47848F?logo=electron&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

## Возможности

| Колесо | macOS | Windows | Что делает |
|---|---|---|---|
| Форматы | `Shift` | `Shift` | Конвертация фото, видео, аудио и документов в нужный формат |
| Инструменты | `Command` | `Alt` | Обрезать, сжать, склеить, кадры, водяной знак, пароль для PDF, текст с фото (OCR) |
| Действия | `Control` | `Ctrl` | Копия, путь, ZIP, переименовать, AirDrop, почта |

**Нейросети работают локально:**
- **ИИ-увеличение** фото (×2, ×4, ×8) и видео (×2, ×4) на Real-ESRGAN
- **Удаление фона** с фото
- **Субтитры и расшифровка речи** в SRT или TXT на whisper.cpp

**Также:**
- Сжатие под Telegram, WhatsApp, Instagram, почту или до нужного размера
- Обработка звука: выровнять громкость, убрать шум или тишину, изменить скорость
- Папки с автоконвертацией: новый файл в папке сам конвертируется
- Пакетная обработка: можно перетащить несколько файлов и папки сразу

## Структура

```
macos/     — нативное приложение на Swift / SwiftUI (Swift Package)
windows/   — приложение на Electron (Node.js)
```

## Сборка

### macOS
Нужны macOS 14+, Mac на Apple Silicon и Xcode или Command Line Tools.
```bash
cd macos
bash install.command    # соберёт и установит в «Программы»
```
Для документов, таблиц и EPUB: `brew install --cask libreoffice`.
Для субтитров: `brew install whisper-cpp`.

### Windows
Нужны Node.js 20+ и Windows 10/11 x64.
```bash
cd windows
npm install
npm start          # запуск
npm run dist       # сборка установщика (electron-builder)
```
Модели Real-ESRGAN и whisper, а также qpdf не входят в репозиторий из-за размера: их кладут в `windows/assets/` перед сборкой. Подробнее в [windows/README-Windows.txt](windows/README-Windows.txt).

## Лицензия

[MIT](LICENSE) © 2026 Bakhtiyor Sattorov
