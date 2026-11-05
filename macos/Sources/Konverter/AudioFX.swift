import AppKit

struct AudioEffect {
    let title: String
    let suffix: String
    let filter: String?
    let speed: Double?
}

/// Эффекты для звука: громкость, шум, тишина, скорость (работает и для видео со звуком)
@MainActor
enum AudioFX {
    static let effects: [AudioEffect] = [
        AudioEffect(title: "Выровнять громкость", suffix: "громкость", filter: "loudnorm=I=-16:TP=-1.5:LRA=11", speed: nil),
        AudioEffect(title: "Убрать шум", suffix: "без шума", filter: "afftdn=nf=-25", speed: nil),
        AudioEffect(title: "Убрать тишину", suffix: "без пауз",
                    filter: "silenceremove=start_periods=1:start_threshold=-45dB:stop_periods=-1:stop_threshold=-45dB:stop_duration=0.6", speed: nil),
        AudioEffect(title: "Ускорить ×1.5", suffix: "×1.5", filter: nil, speed: 1.5),
        AudioEffect(title: "Ускорить ×2", suffix: "×2", filter: nil, speed: 2.0),
        AudioEffect(title: "Замедлить ×0.75", suffix: "×0.75", filter: nil, speed: 0.75),
        AudioEffect(title: "Замедлить ×0.5", suffix: "×0.5", filter: nil, speed: 0.5)
    ]

    private static let codecs: [String: [String]] = [
        "mp3": ["-c:a", "libmp3lame", "-q:a", "2"], "m4a": ["-c:a", "aac", "-b:a", "256k"], "aac": ["-c:a", "aac", "-b:a", "256k"],
        "wav": ["-c:a", "pcm_s16le"], "flac": ["-c:a", "flac"], "ogg": ["-c:a", "libvorbis", "-q:a", "6"],
        "opus": ["-c:a", "libopus", "-b:a", "160k"], "aiff": ["-c:a", "pcm_s16be"]
    ]

    static func ask() async -> AudioEffect? {
        guard let r = await Dialogs.show(title: "Звук", message: "Что сделать со звуком?",
                                         buttons: effects.map { $0.title }, vertical: true) else { return nil }
        return effects[r.button]
    }

    private static func ff(_ args: [String], to out: URL) async throws -> URL {
        let exe = try Converter.requireFFmpeg()
        do {
            try await Converter.run(exe, ["-y", "-nostdin", "-hide_banner"] + args + [out.path])
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return out
    }

    private static func outURL(_ src: URL, _ suffix: String, _ ext: String) -> URL {
        let base = src.deletingPathExtension().lastPathComponent
        return Converter.uniqueOut(dir: Converter.outputDir(for: src), base: "\(base) (\(suffix))", ext: ext)
    }

    static func apply(_ src: URL, _ fx: AudioEffect) async throws -> URL {
        let ext = Formats.norm(src.pathExtension)
        let text = await Converter.probeText(src)
        let hasAudio = text.contains("Audio:")
        let hasVideo = text.contains("Video:")

        if Formats.kind(of: ext) == .audio || !hasVideo {
            guard hasAudio else { throw ConvertError.msg("В этом файле нет звука") }
            let outExt = codecs[ext] != nil ? ext : "mp3"
            let filter: String = fx.speed.map { "atempo=\($0)" } ?? fx.filter ?? ""
            return try await ff(["-i", src.path, "-vn", "-af", filter] + (codecs[outExt] ?? []), to: outURL(src, fx.suffix, outExt))
        }

        let outExt = ["mp4", "mov", "mkv"].contains(ext) ? ext : "mp4"
        if let s = fx.speed {
            let parts: [String]
            if hasAudio {
                parts = ["-filter_complex", "[0:v]setpts=PTS/\(s)[v];[0:a]atempo=\(s)[a]", "-map", "[v]", "-map", "[a]", "-c:a", "aac", "-b:a", "192k"]
            } else {
                parts = ["-filter_complex", "[0:v]setpts=PTS/\(s)[v]", "-map", "[v]", "-an"]
            }
            return try await ff(["-i", src.path] + parts + ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p"],
                                to: outURL(src, fx.suffix, outExt))
        }
        guard hasAudio else { throw ConvertError.msg("В этом видео нет звука") }
        return try await ff(["-i", src.path, "-c:v", "copy", "-af", fx.filter ?? "", "-c:a", "aac", "-b:a", "192k"],
                            to: outURL(src, fx.suffix, outExt))
    }
}
