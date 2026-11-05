# Konverter

**Free offline file converter with a radial "format wheel" for macOS and Windows.**

Start dragging a file, hold a modifier key, and a wheel appears around the cursor. Drop the file on a segment and the result is saved next to the original. Everything works offline.

![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Platform](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6?logo=windows)
![Swift](https://img.shields.io/badge/SwiftUI-F05138?logo=swift&logoColor=white)
![Electron](https://img.shields.io/badge/Electron-47848F?logo=electron&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

| Wheel | macOS | Windows | What it does |
|---|---|---|---|
| Formats | `Shift` | `Shift` | Convert images, video, audio and documents to another format |
| Tools | `Command` | `Alt` | Trim, compress, merge, extract frames, watermark, PDF password, text from image (OCR) |
| Actions | `Control` | `Ctrl` | Duplicate, copy path, ZIP, rename, AirDrop, email |

**On-device AI:**
- **AI upscaling** for images (×2, ×4, ×8) and video (×2, ×4) with Real-ESRGAN
- **Background removal** for images
- **Subtitles and speech-to-text** (SRT or TXT) with whisper.cpp

**Also:**
- Compress for Telegram, WhatsApp, Instagram, email, or to a target size
- Audio processing: normalize loudness, remove noise or silence, change speed
- Watch folders: new files are converted automatically
- Batch processing: drag multiple files and folders at once

## Project structure

```
macos/     — native app in Swift / SwiftUI (Swift Package)
windows/   — Electron app (Node.js)
```

## Building

### macOS
Requires macOS 14+, Apple Silicon, and Xcode or Command Line Tools.
```bash
cd macos
bash install.command    # builds and installs into /Applications
```
For office documents, spreadsheets and EPUB: `brew install --cask libreoffice`.
For subtitles: `brew install whisper-cpp`.

### Windows
Requires Node.js 20+ and Windows 10/11 x64.
```bash
cd windows
npm install
npm start          # run the app
npm run dist       # build the installer (electron-builder)
```
The Real-ESRGAN and whisper models and qpdf are not included in the repository because of their size. Put them in `windows/assets/` before building. See [windows/README-Windows.txt](windows/README-Windows.txt) for details (in Russian).

## License

[MIT](LICENSE) © 2026 Bakhtiyor Sattorov
