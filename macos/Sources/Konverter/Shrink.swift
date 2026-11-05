import AppKit

struct ShrinkPlan {
    let title: String
    let work: (URL) async throws -> URL
}

/// Сжатие до нужного размера (в МБ) и готовые профили для Telegram, WhatsApp, сайта, почты
@MainActor
enum Shrink {
    private static let MB = 1024.0 * 1024.0

    private static func trimNum(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }

    private static func fmtDur(_ s: Double) -> String {
        let m = Int(s) / 60
        return m > 0 ? "\(m) мин \(Int(s.rounded()) % 60) с" : "\(Int(s.rounded())) с"
    }

    private static func outURL(_ src: URL, _ suffix: String, _ ext: String) -> URL {
        let base = src.deletingPathExtension().lastPathComponent
        return Converter.uniqueOut(dir: Converter.outputDir(for: src), base: "\(base) (\(suffix))", ext: ext)
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

    private static func fileSize(_ url: URL) -> Double {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.doubleValue ?? Double.infinity
    }

    // MARK: вопросы
    static func ask(kind: Kind, quick: @escaping (URL) async throws -> URL) async -> ShrinkPlan? {
        guard let r = await Dialogs.show(title: "Сжать", message: "Как сжимать?",
                                         buttons: ["Для мессенджера или сайта…", "До нужного размера…", "Просто сжать (среднее качество)"],
                                         vertical: true) else { return nil }
        if r.button == 2 { return ShrinkPlan(title: "Сжимаю…", work: quick) }

        if r.button == 0 {
            let list = profiles(kind)
            guard let p = await Dialogs.show(title: "Для чего?", message: "Выбери готовый вариант",
                                             buttons: list.map { $0.0 }, vertical: true) else { return nil }
            let chosen = list[p.button]
            return ShrinkPlan(title: "\(chosen.0)…", work: chosen.1)
        }

        let sizes: [Double] = [8, 16, 25, 50]
        var titles = sizes.map { "До \(Int($0)) МБ" }
        titles.append("Свой размер…")
        guard let s = await Dialogs.show(title: "До какого размера?",
                                         message: "Файл будет сжат так, чтобы уложиться в этот размер.",
                                         buttons: titles, vertical: true) else { return nil }
        var mb = 0.0
        if s.button < sizes.count {
            mb = sizes[s.button]
        } else {
            guard let c = await Dialogs.show(title: "Свой размер", message: "Сколько мегабайт?",
                                             fields: [DialogField(label: "", value: "10")], buttons: ["OK"]),
                  let v = Double(c.values[0].replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
            mb = v
        }
        let target = mb
        return ShrinkPlan(title: "Сжимаю до \(trimNum(target)) МБ…", work: { try await toSize(kind, $0, mb: target) })
    }

    private static func toSize(_ kind: Kind, _ url: URL, mb: Double) async throws -> URL {
        switch kind {
        case .video: return try await shrinkVideo(url, mb: mb)
        case .audio: return try await shrinkAudio(url, mb: mb)
        default: return try await shrinkImage(url, mb: mb)
        }
    }

    // MARK: профили
    private static func profiles(_ kind: Kind) -> [(String, (URL) async throws -> URL)] {
        switch kind {
        case .video:
            return [
                ("Telegram (720p)", { try await encodeVideo($0, height: 720, crf: 26, audio: 128, suffix: "Telegram") }),
                ("WhatsApp (до 16 МБ)", { try await shrinkVideo($0, mb: 16) }),
                ("Instagram (1080p)", { try await encodeVideo($0, height: 1080, crf: 23, audio: 160, suffix: "Instagram") }),
                ("Почта (до 25 МБ)", { try await shrinkVideo($0, mb: 25) }),
                ("Сайт (720p, быстрый старт)", { try await encodeVideo($0, height: 720, crf: 27, audio: 96, suffix: "для сайта") })
            ]
        case .audio:
            return [
                ("Голосовое (M4A, моно, 64 кбит/с)", { try await encodeAudio($0, fmt: "m4a", kbps: 64, mono: true, suffix: "голосовое") }),
                ("Подкаст (MP3, моно, 96 кбит/с)", { try await encodeAudio($0, fmt: "mp3", kbps: 96, mono: true, suffix: "подкаст") }),
                ("Музыка (MP3, 320 кбит/с)", { try await encodeAudio($0, fmt: "mp3", kbps: 320, mono: false, suffix: "музыка") })
            ]
        default:
            return [
                ("Telegram (JPG, до 2560 px)", { try await encodeImage($0, fmt: "jpg", maxSide: 2560, q: 85, suffix: "Telegram") }),
                ("Сайт (WEBP, до 1920 px)", { try await encodeImage($0, fmt: "webp", maxSide: 1920, q: 80, suffix: "для сайта") }),
                ("Почта (JPG, до 1 МБ)", { try await shrinkImage($0, mb: 1) }),
                ("Instagram (JPG, до 1350 px)", { try await encodeImage($0, fmt: "jpg", maxSide: 1350, q: 90, suffix: "Instagram") }),
                ("Аватар (PNG, 512 px)", { try await encodeImage($0, fmt: "png", maxSide: 512, q: 90, suffix: "аватар") })
            ]
        }
    }

    // MARK: видео
    private static func shrinkVideo(_ src: URL, mb: Double) async throws -> URL {
        guard let dur = await Converter.probeDuration(src), dur > 0 else {
            throw ConvertError.msg("Не удалось узнать длительность видео")
        }
        let size = await Converter.probeVideoSize(src)
        let hasAudio = await Converter.probeText(src).contains("Audio:")
        let budget = mb * MB * 8 * 0.92
        var audio = hasAudio ? 128_000.0 : 0.0
        var vbr = budget / dur - audio
        if vbr < 150_000 && hasAudio {
            audio = 64_000
            vbr = budget / dur - audio
        }
        if vbr < 80_000 {
            throw ConvertError.msg("Для видео длиной \(fmtDur(dur)) \(trimNum(mb)) МБ слишком мало. Выбери размер побольше.")
        }
        let out = outURL(src, "до \(trimNum(mb)) МБ", "mp4")
        for factor in [1.0, 0.85, 0.7] {
            let rate = Int(vbr * factor)
            let h = rate < 350_000 ? 360 : rate < 900_000 ? 480 : rate < 2_500_000 ? 720 : 0
            var args: [String] = ["-i", src.path]
            if h > 0, let s = size, s.1 > h { args += ["-vf", "scale=-2:\(h)"] }
            args += ["-c:v", "libx264", "-preset", "medium", "-b:v", "\(rate)", "-maxrate", "\(Int(Double(rate) * 1.2))",
                     "-bufsize", "\(rate * 2)", "-pix_fmt", "yuv420p"]
            if hasAudio { args += ["-c:a", "aac", "-b:a", "\(Int(audio))"] } else { args.append("-an") }
            args += ["-movflags", "+faststart"]
            _ = try await ff(args, to: out)
            if fileSize(out) <= mb * MB { return out }
        }
        try? FileManager.default.removeItem(at: out)
        throw ConvertError.msg("Не удалось уложиться в \(trimNum(mb)) МБ. Выбери размер побольше.")
    }

    private static func encodeVideo(_ src: URL, height: Int, crf: Int, audio: Int, suffix: String) async throws -> URL {
        try await ff(["-i", src.path, "-vf", "scale=-2:'min(\(height),ih)'", "-c:v", "libx264", "-preset", "medium",
                      "-crf", "\(crf)", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "\(audio)k", "-movflags", "+faststart"],
                     to: outURL(src, suffix, "mp4"))
    }

    // MARK: звук
    private static func shrinkAudio(_ src: URL, mb: Double) async throws -> URL {
        guard let dur = await Converter.probeDuration(src), dur > 0 else {
            throw ConvertError.msg("Не удалось узнать длительность звука")
        }
        var kbps = Int(mb * MB * 8 * 0.95 / dur / 1000)
        if kbps < 24 { throw ConvertError.msg("Для записи длиной \(fmtDur(dur)) \(trimNum(mb)) МБ слишком мало.") }
        kbps = min(kbps, 320)
        let out = outURL(src, "до \(trimNum(mb)) МБ", "mp3")
        for factor in [1.0, 0.88, 0.75] {
            let rate = max(24, Int(Double(kbps) * factor))
            _ = try await ff(["-i", src.path, "-vn", "-c:a", "libmp3lame", "-b:a", "\(rate)k"], to: out)
            if fileSize(out) <= mb * MB { return out }
        }
        try? FileManager.default.removeItem(at: out)
        throw ConvertError.msg("Не удалось уложиться в \(trimNum(mb)) МБ. Выбери размер побольше.")
    }

    private static func encodeAudio(_ src: URL, fmt: String, kbps: Int, mono: Bool, suffix: String) async throws -> URL {
        var args: [String] = ["-i", src.path, "-vn", "-c:a", fmt == "m4a" ? "aac" : "libmp3lame", "-b:a", "\(kbps)k"]
        if mono { args += ["-ac", "1"] }
        return try await ff(args, to: outURL(src, suffix, fmt))
    }

    // MARK: фото
    private static func readableInput(_ src: URL) async throws -> (url: URL, temp: URL?) {
        let ext = Formats.norm(src.pathExtension)
        if ["heic", "pdf", "tiff"].contains(ext) {
            let t = try await Resize.tempPNG(from: src, ext: ext)
            return (t, t)
        }
        return (src, nil)
    }

    private static func encodeImage(_ src: URL, fmt: String, maxSide: Int, q: Int, suffix: String) async throws -> URL {
        let prepared = try await readableInput(src)
        defer { if let t = prepared.temp { try? FileManager.default.removeItem(at: t) } }
        var args: [String] = ["-i", prepared.url.path, "-frames:v", "1",
                              "-vf", "scale='min(\(maxSide),iw)':'min(\(maxSide),ih)':force_original_aspect_ratio=decrease"]
        if fmt == "jpg" {
            let qs = max(2, min(31, Int((31.0 - Double(q) * 0.29).rounded())))
            args += ["-q:v", String(qs)]
        } else if fmt == "webp" {
            args += ["-quality", String(q)]
        }
        return try await ff(args, to: outURL(src, suffix, fmt))
    }

    private static func shrinkImage(_ src: URL, mb: Double) async throws -> URL {
        let prepared = try await readableInput(src)
        defer { if let t = prepared.temp { try? FileManager.default.removeItem(at: t) } }
        let out = outURL(src, "до \(trimNum(mb)) МБ", "jpg")
        for scale in [1.0, 0.85, 0.7, 0.55, 0.4, 0.3] {
            for q in [3, 5, 8, 11, 15, 20, 26, 31] {
                let vf = scale == 1.0 ? "format=yuvj420p" : "scale=trunc(iw*\(scale)/2)*2:-2,format=yuvj420p"
                _ = try await ff(["-i", prepared.url.path, "-frames:v", "1", "-vf", vf, "-q:v", String(q)], to: out)
                if fileSize(out) <= mb * MB { return out }
            }
        }
        try? FileManager.default.removeItem(at: out)
        throw ConvertError.msg("Не удалось уложиться в \(trimNum(mb)) МБ. Выбери размер побольше.")
    }
}
