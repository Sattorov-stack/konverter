import Foundation

enum ConvertError: LocalizedError {
    case msg(String)
    var errorDescription: String? {
        switch self {
        case .msg(let m): return m
        }
    }
}

final class Tail: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func add(_ s: String) { lock.lock(); text = String((text + s).suffix(1500)); lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return text }
}

final class DurationBox: @unchecked Sendable { var seconds: Double = 0 }

enum Converter {
    // MARK: поиск инструментов
    static func ffmpegPath() -> String? {
        if let p = Bundle.main.path(forResource: "ffmpeg", ofType: nil) { return p }
        for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    static func sofficePath() -> String? {
        let home = NSHomeDirectory()
        let list = ["/Applications/LibreOffice.app/Contents/MacOS/soffice",
                    home + "/Applications/LibreOffice.app/Contents/MacOS/soffice"]
        return list.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let noFFmpeg = "Не найден ffmpeg. Установи его командой: brew install ffmpeg"
    static let noOffice = "Для этого файла нужен бесплатный LibreOffice (libreoffice.org). Установи его один раз, например командой: brew install --cask libreoffice"

    static func requireFFmpeg() throws -> String {
        guard let f = ffmpegPath() else { throw ConvertError.msg(noFFmpeg) }
        return f
    }

    static func nativeDocSupports(_ kind: Kind, _ target: String) -> Bool {
        switch kind {
        case .doc: return ["pdf", "docx", "txt", "html", "rtf", "odt", "png", "jpg"].contains(target)
        case .pdf: return target == "txt"
        default: return false
        }
    }

    // MARK: запуск процесса
    static func run(_ exe: String, _ args: [String], onOutput: (@Sendable (String) -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let pipe = Pipe()
            p.standardError = pipe
            p.standardOutput = pipe
            let tail = Tail()
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
                tail.add(s)
                onOutput?(s)
            }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let last = tail.value.split(separator: "\n").suffix(3).joined(separator: " ")
                    cont.resume(throwing: ConvertError.msg(last.isEmpty ? "Ошибка конвертации" : last))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    static func capture(_ exe: String, _ args: [String]) async throws -> String {
        let t = Tail()
        try await run(exe, args) { t.add($0) }
        return t.value
    }

    static func numbers(_ pattern: String, in s: String, last: Bool = false) -> [Double]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard let m = last ? matches.last : matches.first, m.numberOfRanges == 4 else { return nil }
        var result: [Double] = []
        for i in 1...3 {
            guard let v = Double(ns.substring(with: m.range(at: i))) else { return nil }
            result.append(v)
        }
        return result
    }

    /// Длительность видео или звука в секундах
    static func probeDuration(_ url: URL) async -> Double? {
        guard let ff = ffmpegPath() else { return nil }
        let text: String = await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ff)
            p.arguments = ["-hide_banner", "-i", url.path]
            let pipe = Pipe()
            p.standardError = pipe
            p.standardOutput = pipe
            p.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do { try p.run() } catch { cont.resume(returning: "") }
        }
        guard let d = numbers("Duration: (\\d+):(\\d+):([\\d.]+)", in: text) else { return nil }
        return d[0] * 3600 + d[1] * 60 + d[2]
    }

    /// Весь текст, который ffmpeg выводит про файл (размер, частота кадров и т.д.)
    static func probeText(_ url: URL) async -> String {
        guard let ff = ffmpegPath() else { return "" }
        return await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ff)
            p.arguments = ["-hide_banner", "-i", url.path]
            let pipe = Pipe()
            p.standardError = pipe
            p.standardOutput = pipe
            p.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do { try p.run() } catch { cont.resume(returning: "") }
        }
    }

    /// Размер картинки или видео в пикселях
    static func probeVideoSize(_ url: URL) async -> (Int, Int)? {
        let text = await probeText(url)
        guard let re = try? NSRegularExpression(pattern: "[ ,](\\d{2,5})x(\\d{2,5})[ ,\\[]") else { return nil }
        for line in text.split(separator: "\n") where line.contains("Video:") {
            let s = String(line)
            let ns = s as NSString
            if let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
               let w = Int(ns.substring(with: m.range(at: 1))),
               let h = Int(ns.substring(with: m.range(at: 2))) {
                return (w, h)
            }
        }
        return nil
    }

    static func probeFPS(_ url: URL) async -> Double? {
        let text = await probeText(url)
        guard let re = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?) fps") else { return nil }
        for line in text.split(separator: "\n") where line.contains("Video:") {
            let s = String(line)
            let ns = s as NSString
            if let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
               let v = Double(ns.substring(with: m.range(at: 1))) {
                return v
            }
        }
        return nil
    }

    // MARK: куда сохранять
    static func outputDir(for src: URL) -> URL {
        let parent = src.deletingLastPathComponent()
        let fm = FileManager.default
        switch Prefs.saveMode {
        case 1:
            let d = parent.appendingPathComponent("Converted", isDirectory: true)
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
            return d
        case 2:
            if let p = Prefs.outputFolder {
                let d = URL(fileURLWithPath: p, isDirectory: true)
                try? fm.createDirectory(at: d, withIntermediateDirectories: true)
                return d
            }
            return parent
        default:
            return parent
        }
    }

    static func uniqueOut(dir: URL, base: String, ext: String) -> URL {
        func name(_ b: String) -> String { ext.isEmpty ? b : "\(b).\(ext)" }
        var url = dir.appendingPathComponent(name(base))
        var i = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(name("\(base) (\(i))"))
            i += 1
        }
        return url
    }

    // MARK: фото
    static let sipsIn: Set<String> = ["heic", "jpg", "png", "gif", "tiff", "bmp", "pdf"]
    static let sipsOut = ["jpg": "jpeg", "png": "png", "tiff": "tiff", "bmp": "bmp", "gif": "gif", "pdf": "pdf", "heic": "heic"]

    static func ffmpegImageOpts(_ target: String) -> [String] {
        let q = Prefs.imageQuality
        switch target {
        case "jpg":
            let qs = max(2, min(31, Int((31.0 - Double(q) * 0.29).rounded())))
            return ["-q:v", String(qs)]
        case "webp":
            return ["-c:v", "libwebp", "-quality", String(q)]
        case "avif":
            let crf = max(10, min(50, Int((63.0 - Double(q) * 0.5).rounded())))
            return ["-c:v", "libaom-av1", "-still-picture", "1", "-crf", String(crf)]
        default:
            return []
        }
    }

    static func pixelSize(_ url: URL) async -> (Int, Int)? {
        guard let text = try? await capture("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", url.path]) else { return nil }
        var w: Int?
        var h: Int?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":")
            guard parts.count == 2 else { continue }
            let v = Int(parts[1].trimmingCharacters(in: .whitespaces))
            if parts[0].contains("pixelWidth") { w = v }
            if parts[0].contains("pixelHeight") { h = v }
        }
        if let w = w, let h = h { return (w, h) }
        return nil
    }

    /// Уменьшаем только если картинка больше выбранного предела (sips -Z иначе увеличивает маленькие)
    static func resizeArgs(for url: URL) async -> [String] {
        let n = Prefs.imageMaxSide
        guard n > 0, let size = await pixelSize(url), max(size.0, size.1) > n else { return [] }
        return ["-Z", String(n)]
    }

    static func ffImage(_ src: URL, _ target: String, _ out: URL) async throws {
        let ff = try requireFFmpeg()
        let n = Prefs.imageMaxSide
        var scale: [String] = []
        if n > 0 {
            scale = ["-vf", "scale='min(\(n),iw)':'min(\(n),ih)':force_original_aspect_ratio=decrease"]
        }
        let args: [String] = ["-y", "-nostdin", "-hide_banner", "-i", src.path, "-frames:v", "1"]
            + scale + ffmpegImageOpts(target) + [out.path]
        try await run(ff, args)
    }

    static func image(src: URL, ext: String, target: String, out: URL) async throws {
        let sips = "/usr/bin/sips"
        let resize = await resizeArgs(for: src)
        if sipsIn.contains(ext) {
            if let format = sipsOut[target] {
                var args: [String] = ["-s", "format", format]
                if target == "jpg" || target == "heic" { args += ["-s", "formatOptions", String(Prefs.imageQuality)] }
                args += resize
                args += [src.path, "--out", out.path]
                try await run(sips, args)
            } else {
                // webp / avif на выходе: сначала png через sips, потом ffmpeg
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("konv-\(UUID().uuidString).png")
                defer { try? FileManager.default.removeItem(at: tmp) }
                try await run(sips, ["-s", "format", "png"] + resize + [src.path, "--out", tmp.path])
                try await ffImage(tmp, target, out)
            }
        } else {
            try await ffImage(src, target, out)
        }
    }

    // MARK: музыка и видео
    static func audioArgs(_ target: String) -> [String]? {
        let b = "\(Prefs.audioBitrate)k"
        switch target {
        case "mp3": return ["-c:a", "libmp3lame", "-b:a", b]
        case "m4a": return ["-c:a", "aac", "-b:a", b]
        case "wav": return ["-c:a", "pcm_s16le"]
        case "flac": return ["-c:a", "flac"]
        case "ogg": return ["-c:a", "libvorbis", "-b:a", b]
        case "opus": return ["-c:a", "libopus", "-b:a", b]
        case "aiff": return ["-c:a", "pcm_s16be"]
        default: return nil
        }
    }

    static func videoArgs(_ target: String) -> [String]? {
        let crf: String
        let vp9: String
        switch Prefs.videoQuality {
        case 0:
            crf = "18"
            vp9 = "24"
        case 2:
            crf = "28"
            vp9 = "38"
        default:
            crf = "22"
            vp9 = "31"
        }
        let h = Prefs.videoMaxHeight
        let scale: [String] = h > 0 ? ["-vf", "scale=-2:'min(\(h),ih)'"] : []
        let h264: [String] = scale + ["-c:v", "libx264", "-preset", "medium", "-crf", crf,
                                      "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"]
        switch target {
        case "mp4": return h264 + ["-movflags", "+faststart"]
        case "mov", "mkv": return h264
        case "webm": return scale + ["-c:v", "libvpx-vp9", "-crf", vp9, "-b:v", "0", "-c:a", "libopus"]
        case "avi": return scale + ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame"]
        case "wmv": return scale + ["-c:v", "wmv2", "-b:v", "4M", "-c:a", "wmav2", "-b:a", "192k"]
        case "gif": return ["-an", "-vf", "fps=12,scale=480:-1:flags=lanczos", "-loop", "0"]
        default: return nil
        }
    }

    static func media(src: URL, target: String, out: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let ff = try requireFFmpeg()
        var codec: [String] = []
        if let a = audioArgs(target) {
            codec = ["-vn"] + a
        } else if let v = videoArgs(target) {
            codec = v
        }
        let args: [String] = ["-y", "-nostdin", "-hide_banner", "-i", src.path] + codec + [out.path]
        let dur = DurationBox()
        try await run(ff, args) { s in
            if let d = numbers("Duration: (\\d+):(\\d+):([\\d.]+)", in: s) {
                dur.seconds = d[0] * 3600 + d[1] * 60 + d[2]
            }
            if dur.seconds > 0, let t = numbers("time=(\\d+):(\\d+):([\\d.]+)", in: s, last: true) {
                progress(min(0.99, (t[0] * 3600 + t[1] * 60 + t[2]) / dur.seconds))
            }
        }
    }

    // MARK: документы
    static func document(src: URL, kind: Kind, target: String, out: URL) async throws {
        guard let office = sofficePath() else {
            // без LibreOffice текстовые документы конвертируем средствами самого macOS
            if nativeDocSupports(kind, target) {
                try await NativeDoc.convert(src: src, kind: kind, target: target, out: out)
                return
            }
            throw ConvertError.msg(noOffice)
        }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("konv-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        var filter = target
        if target == "txt" { filter = "txt:Text (encoded):UTF8" }
        if target == "docx" && kind == .pdf { filter = "docx:MS Word 2007 XML" }

        var args: [String] = ["-env:UserInstallation=file://" + tmp.appendingPathComponent("profile").path, "--headless"]
        if kind == .pdf { args.append("--infilter=writer_pdf_import") }
        args += ["--convert-to", filter, "--outdir", tmp.path, src.path]
        try await run(office, args)

        let names = try fm.contentsOfDirectory(atPath: tmp.path)
        guard let made = names.first(where: { $0.lowercased().hasSuffix("." + target) }) else {
            throw ConvertError.msg("Не удалось конвертировать этот файл")
        }
        try fm.copyItem(at: tmp.appendingPathComponent(made), to: out)
    }

    // MARK: главный вход
    static func convert(_ src: URL, kind: Kind, ext: String, target: String, keepOriginal: Bool = false, outDir: URL? = nil,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let base = src.deletingPathExtension().lastPathComponent
        let dir = outDir ?? outputDir(for: src)
        if outDir != nil { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        let out = uniqueOut(dir: dir, base: base, ext: target)
        do {
            switch kind {
            case .image:
                try await image(src: src, ext: ext, target: target, out: out)
            case .pdf where target == "jpg" || target == "png":
                try await image(src: src, ext: ext, target: target, out: out)
            case .audio, .video:
                try await media(src: src, target: target, out: out, progress: progress)
            default:
                try await document(src: src, kind: kind, target: target, out: out)
            }
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        if !keepOriginal && Prefs.trashOriginal && out != src {
            try? FileManager.default.trashItem(at: src, resultingItemURL: nil)
        }
        return out
    }
}
