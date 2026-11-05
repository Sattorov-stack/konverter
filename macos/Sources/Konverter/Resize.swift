import AppKit

struct ResizeSpec {
    enum Mode {
        case factor(Double)
        case width(Int)
        case size(Int, Int)
    }
    let mode: Mode
    let label: String
}

/// Изменение размера (увеличить или уменьшить) и ИИ-увеличение фото и видео
@MainActor
enum Resize {
    static let maxSide = 16384        // для фото
    static let maxVideoSide = 8192    // для видео

    static let noAI = "ИИ-модуль не найден. Запусти установку заново (bash install.command), интернет нужен один раз."

    // MARK: вопросы
    static func ask(isVideo: Bool) async -> ResizeSpec? {
        let hint = isVideo
            ? "Видео меняет размер обычным сглаживанием: быстро, но новых деталей не появится."
            : "Фото меняет размер обычным сглаживанием: быстро, но новых деталей не появится. Для настоящего улучшения есть «ИИ-увеличение»."
        guard let r = await Dialogs.show(title: "Размер", message: hint,
                                         buttons: ["×2", "×4", "×8", "×½", "×¼", "Свой размер…"], vertical: true) else { return nil }
        switch r.button {
        case 0: return ResizeSpec(mode: .factor(2), label: "×2")
        case 1: return ResizeSpec(mode: .factor(4), label: "×4")
        case 2: return ResizeSpec(mode: .factor(8), label: "×8")
        case 3: return ResizeSpec(mode: .factor(0.5), label: "×½")
        case 4: return ResizeSpec(mode: .factor(0.25), label: "×¼")
        default: return await askCustom()
        }
    }

    private static func askCustom() async -> ResizeSpec? {
        var message = "Примеры: 3200 (ширина в пикселях), 3200x2400, 400%, ×4, 0.5. Число меньше 50 значит «во сколько раз»."
        var text = ""
        while true {
            guard let r = await Dialogs.show(title: "Свой размер", message: message,
                                             fields: [DialogField(label: "", value: text)], buttons: ["OK"]) else { return nil }
            text = r.values[0]
            if let spec = parse(text) { return spec }
            message = "Не понял. Примеры: 3200, 3200x2400, 400%, ×4, 0.5"
        }
    }

    static func parse(_ raw: String) -> ResizeSpec? {
        var t = raw.lowercased().replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        t = t.replacingOccurrences(of: "×", with: "x").replacingOccurrences(of: "х", with: "x")
        t = t.replacingOccurrences(of: "px", with: "")
        if t.hasSuffix("%"), let v = Double(t.dropLast()), v > 0 {
            return ResizeSpec(mode: .factor(v / 100), label: "\(Int(v.rounded()))%")
        }
        if t.hasPrefix("x"), let v = Double(t.dropFirst()), v > 0 {
            return ResizeSpec(mode: .factor(v), label: "×\(trim(v))")
        }
        if t.hasSuffix("x"), let v = Double(t.dropLast()), v > 0 {
            return ResizeSpec(mode: .factor(v), label: "×\(trim(v))")
        }
        let parts = t.split(separator: "x").map(String.init)
        if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 {
            return ResizeSpec(mode: .size(w, h), label: "\(w)x\(h)")
        }
        if parts.count == 1, let v = Double(parts[0]), v > 0 {
            if v < 50 { return ResizeSpec(mode: .factor(v), label: "×\(trim(v))") }
            return ResizeSpec(mode: .width(Int(v)), label: "\(Int(v)) px")
        }
        return nil
    }

    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    static func askAIFactor(video: Bool) async -> Int? {
        var message = "ИИ дорисовывает детали: лучше всего работает на фото и рисунках. На совсем маленьких снимках лица и текст могут получиться «придуманными»."
        var buttons = ["×2", "×4"]
        if video {
            message += "\nВидео обрабатывается кадр за кадром: это долго и занимает много места на диске."
        } else {
            buttons.append("×8")
            message += "\n×8 делается в два прохода и занимает заметно дольше."
        }
        guard let r = await Dialogs.show(title: "ИИ-увеличение", message: message, buttons: buttons, vertical: true) else { return nil }
        return [2, 4, 8][r.button]
    }

    static func confirmVideoAI(_ src: URL, factor: Int) async -> Bool {
        let dur = await Converter.probeDuration(src) ?? 0
        let fps = await Converter.probeFPS(src) ?? 30
        let size = await Converter.probeVideoSize(src) ?? (1280, 720)
        let frames = max(1, Int(dur * fps))
        let outMP = Double(size.0 * 4) * Double(size.1 * 4) / 1_000_000
        let lo = Int((Double(frames) * outMP * 0.5 / 60).rounded(.up))
        let hi = Int((Double(frames) * outMP * 1.5 / 60).rounded(.up))
        let gb = Double(frames) * outMP * 0.5 / 1000
        let message = "В видео около \(frames) кадров. ИИ обрабатывает каждый отдельно: примерно \(lo)–\(hi) мин. и до \(String(format: "%.1f", gb)) ГБ временного места на диске. Mac в это время будет заметно нагружен. Продолжить?"
        return await Dialogs.show(title: "ИИ для видео ×\(factor)", message: message, buttons: ["Начать"]) != nil
    }

    // MARK: расчёт размера
    static func target(_ spec: ResizeSpec, _ w: Int, _ h: Int, even: Bool) -> (Int, Int) {
        let tw: Double
        let th: Double
        switch spec.mode {
        case .factor(let f):
            tw = Double(w) * f
            th = Double(h) * f
        case .width(let nw):
            tw = Double(nw)
            th = Double(h) * Double(nw) / Double(max(w, 1))
        case .size(let nw, let nh):
            tw = Double(nw)
            th = Double(nh)
        }
        var iw = max(2, Int(tw.rounded()))
        var ih = max(2, Int(th.rounded()))
        if even {
            iw += iw % 2
            ih += ih % 2
        }
        return (iw, ih)
    }

    private static func checkSize(_ w: Int, _ h: Int, video: Bool) throws {
        let limit = video ? maxVideoSide : maxSide
        if max(w, h) > limit {
            throw ConvertError.msg("Получится \(w)×\(h) px. Это слишком много: максимум \(limit) px по большей стороне.")
        }
    }

    static func resize(_ src: URL, _ spec: ResizeSpec) async throws -> URL {
        if Formats.kind(of: src.pathExtension) == .video { return try await resizeVideo(src, spec) }
        return try await resizeImage(src, spec)
    }

    private static func imageSize(_ src: URL) async throws -> (Int, Int) {
        var dims = await Converter.pixelSize(src)
        if dims == nil { dims = await Converter.probeVideoSize(src) }
        guard let d = dims else { throw ConvertError.msg("Не удалось узнать размер картинки") }
        return d
    }

    static func tempPNG(from src: URL, ext: String) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("konv-\(UUID().uuidString).png")
        if ext == "avif" || ext == "webp" {
            let ff = try Converter.requireFFmpeg()
            try await Converter.run(ff, ["-y", "-nostdin", "-hide_banner", "-i", src.path, "-frames:v", "1", tmp.path])
        } else {
            try await Converter.run("/usr/bin/sips", ["-s", "format", "png", src.path, "--out", tmp.path])
        }
        return tmp
    }

    // MARK: фото
    private static func resizeImage(_ src: URL, _ spec: ResizeSpec) async throws -> URL {
        let ff = try Converter.requireFFmpeg()
        let ext = Formats.norm(src.pathExtension)
        let d = try await imageSize(src)
        let (tw, th) = target(spec, d.0, d.1, even: false)
        try checkSize(tw, th, video: false)

        var input = src
        var temp: URL?
        if ["heic", "pdf", "tiff"].contains(ext) {
            let t = try await tempPNG(from: src, ext: ext)
            input = t
            temp = t
        }
        defer { if let t = temp { try? FileManager.default.removeItem(at: t) } }

        let outExt = ["jpg", "png", "webp", "tiff", "bmp", "gif"].contains(ext) ? ext : "png"
        var opts: [String] = []
        if outExt == "jpg" { opts = ["-q:v", "2"] }
        if outExt == "webp" { opts = ["-quality", "95"] }

        let base = src.deletingPathExtension().lastPathComponent
        let out = Converter.uniqueOut(dir: Converter.outputDir(for: src), base: "\(base) (\(spec.label))", ext: outExt)
        let args: [String] = ["-y", "-nostdin", "-hide_banner", "-i", input.path,
                              "-vf", "scale=\(tw):\(th):flags=lanczos"] + opts + [out.path]
        do {
            try await Converter.run(ff, args)
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return out
    }

    // MARK: видео
    private static func videoCodec(_ w: Int, _ h: Int) -> [String] {
        if w <= 4096 && h <= 4096 && w * h <= 8_912_896 {
            return ["-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p"]
        }
        // для очень больших кадров H.264 не подходит: берём HEVC
        return ["-c:v", "libx265", "-preset", "fast", "-crf", "20", "-tag:v", "hvc1", "-pix_fmt", "yuv420p"]
    }

    private static func friendly(_ error: Error) -> Error {
        let text = error.localizedDescription
        if text.contains("libx265") || text.contains("Unknown encoder") {
            return ConvertError.msg("В этом ffmpeg нет кодека HEVC, а для такого размера он нужен. Выбери размер до 4096 px.")
        }
        return error
    }

    private static func resizeVideo(_ src: URL, _ spec: ResizeSpec) async throws -> URL {
        let ff = try Converter.requireFFmpeg()
        guard let d = await Converter.probeVideoSize(src) else { throw ConvertError.msg("Не удалось узнать размер видео") }
        let (tw, th) = target(spec, d.0, d.1, even: true)
        try checkSize(tw, th, video: true)

        let ext = src.pathExtension.lowercased()
        let outExt = ["mp4", "mov", "mkv"].contains(ext) ? ext : "mp4"
        let base = src.deletingPathExtension().lastPathComponent
        let out = Converter.uniqueOut(dir: Converter.outputDir(for: src), base: "\(base) (\(spec.label))", ext: outExt)
        var args: [String] = ["-y", "-nostdin", "-hide_banner", "-i", src.path,
                              "-vf", "scale=\(tw):\(th):flags=lanczos"]
        args += videoCodec(tw, th)
        args += ["-c:a", "aac", "-b:a", "192k"]
        if outExt == "mp4" { args += ["-movflags", "+faststart"] }
        args.append(out.path)
        do {
            try await Converter.run(ff, args)
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw friendly(error)
        }
        return out
    }

    // MARK: ИИ-увеличение
    private static func aiTool() -> (bin: String, models: String)? {
        guard let dir = Bundle.main.resourcePath else { return nil }
        let base = dir + "/realesrgan"
        let bin = base + "/realesrgan-ncnn-vulkan"
        guard FileManager.default.isExecutableFile(atPath: bin) else { return nil }
        return (bin, base + "/models")
    }

    private static func aiRun(_ tool: (bin: String, models: String), _ input: URL, _ output: URL, format: String) async throws {
        try await Converter.run(tool.bin, ["-i", input.path, "-o", output.path, "-n", "realesrgan-x4plus",
                                           "-s", "4", "-m", tool.models, "-f", format])
    }

    static func aiImage(_ src: URL, factor: Int) async throws -> URL {
        guard let tool = aiTool() else { throw ConvertError.msg(noAI) }
        let ff = try Converter.requireFFmpeg()
        let ext = Formats.norm(src.pathExtension)
        let d = try await imageSize(src)
        let finalW = d.0 * factor
        let finalH = d.1 * factor
        try checkSize(finalW, finalH, video: false)
        let passes = factor == 8 ? 2 : 1
        let inter = max(d.0, d.1) * (passes == 2 ? 16 : 4)
        if inter > 24000 {
            throw ConvertError.msg("Для ×\(factor) промежуточный размер получится \(inter) px: это слишком много. Выбери ×4 или ×2.")
        }

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("konv-ai-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // defer внутри if сработал бы сразу, поэтому временный файл удаляем в конце функции
        var input = src
        var tempInput: URL?
        defer { if let t = tempInput { try? fm.removeItem(at: t) } }
        if !["png", "jpg", "webp"].contains(ext) {
            let t = try await tempPNG(from: src, ext: ext)
            tempInput = t
            input = t
        }
        let p1 = tmp.appendingPathComponent("p1.png")
        try await aiRun(tool, input, p1, format: "png")
        var current = p1
        if passes == 2 {
            let p2 = tmp.appendingPathComponent("p2.png")
            try await aiRun(tool, p1, p2, format: "png")
            current = p2
        }

        let outExt = ["jpg", "png", "webp", "tiff"].contains(ext) ? ext : "png"
        var opts: [String] = []
        if outExt == "jpg" { opts = ["-q:v", "2"] }
        if outExt == "webp" { opts = ["-quality", "95"] }
        var scale: [String] = []
        if factor != (passes == 2 ? 16 : 4) { scale = ["-vf", "scale=\(finalW):\(finalH):flags=lanczos"] }

        let base = src.deletingPathExtension().lastPathComponent
        let out = Converter.uniqueOut(dir: Converter.outputDir(for: src), base: "\(base) (ИИ ×\(factor))", ext: outExt)
        do {
            try await Converter.run(ff, ["-y", "-nostdin", "-hide_banner", "-i", current.path] + scale + opts + [out.path])
        } catch {
            try? fm.removeItem(at: out)
            throw error
        }
        return out
    }

    static func aiVideo(_ src: URL, factor: Int) async throws -> URL {
        guard let tool = aiTool() else { throw ConvertError.msg(noAI) }
        let ff = try Converter.requireFFmpeg()
        guard let d = await Converter.probeVideoSize(src) else { throw ConvertError.msg("Не удалось узнать размер видео") }
        let fps = await Converter.probeFPS(src) ?? 30
        let tw = (d.0 * factor + 1) / 2 * 2
        let th = (d.1 * factor + 1) / 2 * 2
        try checkSize(tw, th, video: true)

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("konv-aivideo-\(UUID().uuidString)")
        let framesDir = tmp.appendingPathComponent("frames")
        let upDir = tmp.appendingPathComponent("up")
        try fm.createDirectory(at: framesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: upDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // 1) раскладываем видео на кадры
        try await Converter.run(ff, ["-y", "-nostdin", "-hide_banner", "-i", src.path, "-fps_mode", "passthrough",
                                     "-q:v", "2", framesDir.appendingPathComponent("%08d.jpg").path])
        // 2) ИИ увеличивает каждый кадр
        try await aiRun(tool, framesDir, upDir, format: "jpg")

        // 3) собираем обратно со звуком
        let ext = src.pathExtension.lowercased()
        let outExt = ["mp4", "mov", "mkv"].contains(ext) ? ext : "mp4"
        let base = src.deletingPathExtension().lastPathComponent
        let out = Converter.uniqueOut(dir: Converter.outputDir(for: src), base: "\(base) (ИИ ×\(factor))", ext: outExt)
        var args: [String] = ["-y", "-nostdin", "-hide_banner", "-framerate", String(format: "%.3f", fps),
                              "-i", upDir.appendingPathComponent("%08d.jpg").path, "-i", src.path,
                              "-map", "0:v", "-map", "1:a?"]
        if factor != 4 { args += ["-vf", "scale=\(tw):\(th):flags=lanczos"] }
        args += videoCodec(tw, th)
        args += ["-c:a", "aac", "-b:a", "192k", "-shortest"]
        if outExt == "mp4" { args += ["-movflags", "+faststart"] }
        args.append(out.path)
        do {
            try await Converter.run(ff, args)
        } catch {
            try? fm.removeItem(at: out)
            throw friendly(error)
        }
        return out
    }
}
