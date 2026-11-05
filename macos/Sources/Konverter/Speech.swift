import AppKit

/// Расшифровка речи в текст и субтитры через whisper.cpp (ставится одной командой brew)
@MainActor
enum Speech {
    static func ask() async -> (format: String, lang: String)? {
        guard let f = await Dialogs.show(title: "Речь в текст", message: "Что получить?",
                                         buttons: ["Субтитры (.srt)", "Текст (.txt)"], vertical: true) else { return nil }
        guard let l = await Dialogs.show(title: "Язык речи", message: "На каком языке говорят?",
                                         buttons: ["Определить автоматически", "Русский", "English", "Українська"], vertical: true) else { return nil }
        return (f.button == 0 ? "srt" : "txt", ["auto", "ru", "en", "uk"][l.button])
    }

    private static var downloading = false

    private static func cli() -> String? {
        ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func modelURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Konverter/ggml-base.bin")
    }

    static func transcribe(_ src: URL, format: String, lang: String) async throws -> URL {
        guard let exe = cli() else {
            throw ConvertError.msg("Для распознавания речи нужна бесплатная программа whisper.cpp. Установи её командой: brew install whisper-cpp")
        }
        let ffmpeg = try Converter.requireFFmpeg()
        let fm = FileManager.default
        let model = modelURL()
        let attrs = try? fm.attributesOfItem(atPath: model.path)
        let have = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        if have < 100_000_000 {
            // второй запуск во время скачивания испортил бы файл: просто просим подождать
            if downloading {
                throw ConvertError.msg("Модель распознавания ещё скачивается. Дождись окончания и повтори.")
            }
            downloading = true
            defer { downloading = false }
            ToastController.shared.progress("Скачиваю модель распознавания…", "около 150 МБ, один раз. Это займёт несколько минут")
            try fm.createDirectory(at: model.deletingLastPathComponent(), withIntermediateDirectories: true)
            let part = model.path + ".part"
            try? fm.removeItem(atPath: part)
            do {
                try await Converter.run("/usr/bin/curl", ["-L", "--fail", "-o", part,
                                                           "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"])
                try? fm.removeItem(atPath: model.path)
                try fm.moveItem(atPath: part, toPath: model.path)
            } catch {
                try? fm.removeItem(atPath: part)
                throw ConvertError.msg("Не удалось скачать модель распознавания (около 150 МБ, интернет нужен один раз)")
            }
        }

        ToastController.shared.progress("Распознаю речь…", src.lastPathComponent)
        let tmp = fm.temporaryDirectory.appendingPathComponent("konv-speech-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let wav = tmp.appendingPathComponent("audio.wav")
        try await Converter.run(ffmpeg, ["-y", "-nostdin", "-hide_banner", "-i", src.path, "-vn", "-ar", "16000", "-ac", "1",
                                         "-c:a", "pcm_s16le", wav.path])

        let base = src.deletingPathExtension().lastPathComponent
        let out = Converter.uniqueOut(dir: Converter.outputDir(for: src),
                                      base: "\(base) (\(format == "srt" ? "субтитры" : "текст"))", ext: format)
        let outBase = String(out.path.dropLast(format.count + 1))
        try await Converter.run(exe, ["-m", model.path, "-f", wav.path, "-l", lang,
                                      format == "srt" ? "-osrt" : "-otxt", "-of", outBase])
        guard fm.fileExists(atPath: out.path) else { throw ConvertError.msg("Распознавание не дало результата") }
        return out
    }
}
