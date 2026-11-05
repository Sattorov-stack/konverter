import AppKit
import PDFKit
import Vision

/// Колесо инструментов (Command): обрезать, без звука, сжать, склеить и т.д.
@MainActor
enum Tools {
    static func items(for urls: [URL]) -> [WheelItem] {
        guard let first = urls.first, let kind = Formats.kind(of: first.pathExtension) else { return [] }
        var list: [WheelItem]
        switch kind {
        case .video:
            list = [
                WheelItem(id: "mute", title: "Без звука", symbol: "speaker.slash"),
                WheelItem(id: "trim", title: "Обрезать", symbol: "scissors"),
                WheelItem(id: "compress", title: "Сжать…", symbol: "arrow.down.right.and.arrow.up.left"),
                WheelItem(id: "merge", title: "Склеить", symbol: "rectangle.stack"),
                WheelItem(id: "frames", title: "Кадры", symbol: "photo.on.rectangle"),
                WheelItem(id: "resize", title: "Размер", symbol: "arrow.up.left.and.down.right.magnifyingglass"),
                WheelItem(id: "ai", title: "ИИ-увеличение", symbol: "wand.and.stars"),
                WheelItem(id: "fx", title: "Звук…", symbol: "waveform"),
                WheelItem(id: "subs", title: "Субтитры", symbol: "captions.bubble")
            ]
        case .audio:
            list = [
                WheelItem(id: "trim", title: "Обрезать", symbol: "scissors"),
                WheelItem(id: "compress", title: "Сжать…", symbol: "arrow.down.right.and.arrow.up.left"),
                WheelItem(id: "fx", title: "Звук…", symbol: "waveform"),
                WheelItem(id: "merge", title: "Склеить", symbol: "rectangle.stack"),
                WheelItem(id: "subs", title: "Текст речи", symbol: "captions.bubble")
            ]
        case .image:
            list = [
                WheelItem(id: "compress", title: "Сжать…", symbol: "arrow.down.right.and.arrow.up.left"),
                WheelItem(id: "resize", title: "Размер", symbol: "arrow.up.left.and.down.right.magnifyingglass"),
                WheelItem(id: "rotate", title: "Повернуть", symbol: "rotate.right"),
                WheelItem(id: "strip", title: "Без EXIF", symbol: "location.slash"),
                WheelItem(id: "topdf", title: "В один PDF", symbol: "doc.richtext"),
                WheelItem(id: "ocr", title: "Текст с фото", symbol: "text.viewfinder"),
                WheelItem(id: "watermark", title: "Водяной знак", symbol: "drop"),
                WheelItem(id: "ai", title: "ИИ-увеличение", symbol: "wand.and.stars"),
                WheelItem(id: "bgremove", title: "Убрать фон", symbol: "person.crop.circle.badge.minus")
            ]
        case .pdf:
            list = [
                WheelItem(id: "merge", title: "Объединить", symbol: "rectangle.stack"),
                WheelItem(id: "split", title: "По страницам", symbol: "square.split.2x1"),
                WheelItem(id: "rotate", title: "Повернуть", symbol: "rotate.right"),
                WheelItem(id: "compress", title: "Сжать", symbol: "arrow.down.right.and.arrow.up.left"),
                WheelItem(id: "password", title: "Пароль", symbol: "lock")
            ]
        case .doc, .sheet, .slides:
            list = [WheelItem(id: "topdf", title: "В PDF", symbol: "doc.richtext")]
            if kind == .doc { list.append(WheelItem(id: "totxt", title: "В текст", symbol: "text.alignleft")) }
            if urls.count > 1 { list.append(WheelItem(id: "mergepdf", title: "Склеить в PDF", symbol: "rectangle.stack")) }
        }
        if urls.count < 2 { list.removeAll { $0.id == "merge" } }
        return list
    }

    static func run(_ id: String, _ urls: [URL]) {
        guard let first = urls.first, let kind = Formats.kind(of: first.pathExtension) else { return }
        let toast = ToastController.shared
        let label = urls.count > 1 ? "Файлов: \(urls.count)" : first.lastPathComponent

        switch (kind, id) {
        case (.video, "mute"):
            toast.run("Убираю звук…", label) { try await each(urls, mute) }
        case (.video, "trim"), (.audio, "trim"):
            Task {
                let duration = await Converter.probeDuration(first)
                guard let r = await askRange(duration: duration) else { return }
                toast.run("Обрезаю…", label) { try await each(urls) { try await trim($0, r.0, r.1) } }
            }
        case (.video, "compress"), (.audio, "compress"), (.image, "compress"):
            Task {
                let quick: (URL) async throws -> URL
                switch kind {
                case .video: quick = { try await compressVideo($0) }
                case .audio: quick = { try await compressAudio($0) }
                default: quick = { try await compressImage($0) }
                }
                guard let plan = await Shrink.ask(kind: kind, quick: quick) else { return }
                toast.run(plan.title, label) { try await each(urls, plan.work) }
            }
        case (.image, "bgremove"):
            toast.run("Убираю фон…", label) { try await each(urls) { try await BackgroundRemoval.remove($0) } }
        case (.video, "fx"), (.audio, "fx"):
            Task {
                guard let fx = await AudioFX.ask() else { return }
                toast.run("\(fx.title)…", label) { try await each(urls) { try await AudioFX.apply($0, fx) } }
            }
        case (.video, "subs"), (.audio, "subs"):
            Task {
                guard let o = await Speech.ask() else { return }
                toast.run("Распознаю речь…", label) { try await each(urls) { try await Speech.transcribe($0, format: o.format, lang: o.lang) } }
            }
        case (.video, "merge"), (.audio, "merge"):
            toast.run("Склеиваю…", label) {
                let o = try await merge(urls, kind: kind)
                return [o]
            }
        case (.image, "resize"), (.video, "resize"):
            Task {
                guard let spec = await Resize.ask(isVideo: kind == .video) else { return }
                toast.run("Меняю размер…", label) { try await each(urls) { try await Resize.resize($0, spec) } }
            }
        case (.image, "ai"):
            Task {
                guard let f = await Resize.askAIFactor(video: false) else { return }
                toast.run("ИИ увеличивает фото…", label) { try await each(urls) { try await Resize.aiImage($0, factor: f) } }
            }
        case (.video, "ai"):
            Task {
                guard let f = await Resize.askAIFactor(video: true) else { return }
                guard await Resize.confirmVideoAI(first, factor: f) else { return }
                toast.run("ИИ увеличивает видео… (это долго)", label) { try await each(urls) { try await Resize.aiVideo($0, factor: f) } }
            }
        case (.image, "rotate"):
            toast.run("Поворачиваю…", label) { try await each(urls, rotateImage) }
        case (.image, "strip"):
            toast.run("Убираю метаданные…", label) { try await each(urls, stripMeta) }
        case (.image, "topdf"):
            toast.run("Собираю PDF…", label) {
                let o = try imagesToPDF(urls)
                return [o]
            }
        case (.pdf, "merge"):
            toast.run("Объединяю PDF…", label) {
                let o = try mergePDF(urls)
                return [o]
            }
        case (.pdf, "split"):
            toast.run("Разделяю PDF…", label) { try splitPDF(first) }
        case (.pdf, "rotate"):
            toast.run("Поворачиваю PDF…", label) { try await each(urls) { try rotatePDF($0) } }
        case (.image, "ocr"):
            toast.run("Распознаю текст…", label) { try await each(urls, ocr) }
        case (.doc, "topdf"), (.sheet, "topdf"), (.slides, "topdf"):
            toast.run("Делаю PDF…", label) { try await each(urls) { try await toTarget($0, "pdf") } }
        case (.doc, "totxt"):
            toast.run("Достаю текст…", label) { try await each(urls) { try await toTarget($0, "txt") } }
        case (.doc, "mergepdf"), (.sheet, "mergepdf"), (.slides, "mergepdf"):
            toast.run("Склеиваю в PDF…", label) {
                let o = try await mergeDocsToPDF(urls)
                return [o]
            }
        case (.video, "frames"):
            Task {
                guard let s = await Dialogs.askText(title: "Кадры из видео", message: "Сохранять кадр каждые сколько секунд?", defaultValue: "5"),
                      let n = Double(s.replacingOccurrences(of: ",", with: ".")), n > 0 else { return }
                toast.run("Достаю кадры…", label) { try await each(urls) { try await frames($0, every: n) } }
            }
        case (.image, "watermark"):
            Task {
                guard let t = await Dialogs.askText(title: "Водяной знак", message: "Текст в правом нижнем углу", defaultValue: "© ") else { return }
                toast.run("Ставлю водяной знак…", label) { try await each(urls) { try watermark($0, t) } }
            }
        case (.pdf, "compress"):
            toast.run("Сжимаю PDF…", label) { try await each(urls) { try compressPDF($0) } }
        case (.pdf, "password"):
            Task {
                guard let pw = await Dialogs.askText(title: "Пароль для PDF", message: "Без пароля файл не откроется", secure: true) else { return }
                toast.run("Защищаю PDF…", label) { try await each(urls) { try passwordPDF($0, pw) } }
            }
        default:
            toast.info("Недоступно", "Для этого файла такого инструмента нет")
        }
    }

    // MARK: общее
    private static func each(_ urls: [URL], _ f: (URL) async throws -> URL) async throws -> [URL] {
        var outs: [URL] = []
        for u in urls { outs.append(try await f(u)) }
        return outs
    }

    private static func sorted(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func out(_ src: URL, _ suffix: String, _ ext: String? = nil) -> URL {
        let base = src.deletingPathExtension().lastPathComponent
        return Converter.uniqueOut(dir: Converter.outputDir(for: src),
                                   base: "\(base) (\(suffix))",
                                   ext: ext ?? src.pathExtension)
    }

    private static func ff(_ args: [String], to o: URL) async throws -> URL {
        let exe = try Converter.requireFFmpeg()
        do {
            try await Converter.run(exe, ["-y", "-nostdin", "-hide_banner"] + args + [o.path])
        } catch {
            try? FileManager.default.removeItem(at: o)
            throw error
        }
        return o
    }

    private static func sips(_ args: [String], to o: URL) async throws -> URL {
        do {
            try await Converter.run("/usr/bin/sips", args + ["--out", o.path])
        } catch {
            try? FileManager.default.removeItem(at: o)
            throw error
        }
        return o
    }

    // MARK: видео и звук
    private static func mute(_ src: URL) async throws -> URL {
        try await ff(["-i", src.path, "-an", "-c:v", "copy"], to: out(src, "без звука"))
    }

    private static func compressVideo(_ src: URL) async throws -> URL {
        try await ff(["-i", src.path, "-c:v", "libx264", "-preset", "medium", "-crf", "28",
                      "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"],
                     to: out(src, "сжато", "mp4"))
    }

    private static func compressAudio(_ src: URL) async throws -> URL {
        try await ff(["-i", src.path, "-vn", "-c:a", "libmp3lame", "-b:a", "128k"], to: out(src, "сжато", "mp3"))
    }

    private static func normalize(_ src: URL) async throws -> URL {
        try await ff(["-i", src.path, "-vn", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
                      "-c:a", "libmp3lame", "-q:a", "2"], to: out(src, "громкость", "mp3"))
    }

    private static func trim(_ src: URL, _ start: Double, _ end: Double) async throws -> URL {
        let ext = src.pathExtension.lowercased()
        let from = String(format: "%.3f", start)
        let length = String(format: "%.3f", end - start)
        if Formats.kind(of: ext) == .video {
            // с перекодированием, чтобы обрезка была точной
            let outExt = ["mp4", "mov", "mkv"].contains(ext) ? ext : "mp4"
            return try await ff(["-ss", from, "-i", src.path, "-t", length,
                                 "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
                                 "-c:a", "aac", "-b:a", "192k"], to: out(src, "обрезано", outExt))
        }
        return try await ff(["-ss", from, "-i", src.path, "-t", length,
                             "-c", "copy", "-avoid_negative_ts", "make_zero"], to: out(src, "обрезано"))
    }

    private static func merge(_ urls: [URL], kind: Kind) async throws -> URL {
        let files = sorted(urls)
        guard files.allSatisfy({ Formats.kind(of: $0.pathExtension) == kind }) else {
            throw ConvertError.msg("Склеивать можно только файлы одного типа")
        }
        let list = files.map { "file '" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: "\n")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("konv-\(UUID().uuidString).txt")
        try list.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let codec: [String]
        let ext: String
        if kind == .video {
            codec = ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
                     "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
            ext = "mp4"
        } else {
            codec = ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
            ext = "mp3"
        }
        return try await ff(["-f", "concat", "-safe", "0", "-i", tmp.path] + codec,
                            to: out(files[0], "объединено", ext))
    }

    // MARK: фото
    private static func compressImage(_ src: URL) async throws -> URL {
        let e = Formats.norm(src.pathExtension)
        guard Converter.sipsIn.contains(e) else { throw ConvertError.msg("Для этого формата сжатие пока недоступно") }
        let isHeic = e == "heic"
        return try await sips(["-s", "format", isHeic ? "heic" : "jpeg",
                               "-s", "formatOptions", isHeic ? "55" : "65", src.path],
                              to: out(src, "сжато", isHeic ? "heic" : "jpg"))
    }

    private static func rotateImage(_ src: URL) async throws -> URL {
        let e = Formats.norm(src.pathExtension)
        guard Converter.sipsIn.contains(e) else { throw ConvertError.msg("Для этого формата пока недоступно") }
        return try await sips(["-r", "90", src.path], to: out(src, "повернуто"))
    }

    private static func stripMeta(_ src: URL) async throws -> URL {
        let e = Formats.norm(src.pathExtension)
        if e == "heic" { throw ConvertError.msg("Для HEIC эта функция пока недоступна") }
        var args = ["-i", src.path, "-map_metadata", "-1", "-frames:v", "1"]
        if e == "jpg" { args += ["-q:v", "2"] }
        return try await ff(args, to: out(src, "без метаданных"))
    }

    private static func imagesToPDF(_ urls: [URL]) throws -> URL {
        let files = sorted(urls)
        let doc = PDFDocument()
        for (i, u) in files.enumerated() {
            guard let img = NSImage(contentsOf: u), let page = PDFPage(image: img) else {
                throw ConvertError.msg("Не удалось открыть \(u.lastPathComponent)")
            }
            doc.insert(page, at: i)
        }
        let first = files[0]
        let base = first.deletingPathExtension().lastPathComponent + (files.count > 1 ? " (+\(files.count - 1))" : "")
        let o = Converter.uniqueOut(dir: Converter.outputDir(for: first), base: base, ext: "pdf")
        guard doc.write(to: o) else { throw ConvertError.msg("Не удалось сохранить PDF") }
        return o
    }

    // MARK: кадры, водяной знак, PDF
    private static func frames(_ src: URL, every n: Double) async throws -> URL {
        let base = src.deletingPathExtension().lastPathComponent
        let folder = Converter.uniqueOut(dir: Converter.outputDir(for: src), base: "\(base) (кадры)", ext: "")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            _ = try await ff(["-i", src.path, "-vf", "fps=1/\(n)", "-q:v", "2"],
                             to: folder.appendingPathComponent("кадр_%03d.jpg"))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    private static func watermark(_ src: URL, _ text: String) throws -> URL {
        guard let img = NSImage(contentsOf: src), let rep = img.representations.first else {
            throw ConvertError.msg("Не удалось открыть картинку")
        }
        let w = max(rep.pixelsWide, 1)
        let h = max(rep.pixelsHigh, 1)
        guard let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: bmp) else {
            throw ConvertError.msg("Не удалось подготовить картинку")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1.0)

        let fontSize = CGFloat(min(w, h)) / 12
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = fontSize / 10
        shadow.shadowOffset = NSSize(width: 0, height: -fontSize / 20)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
            .shadow: shadow
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: CGFloat(w) - size.width - fontSize * 0.6, y: fontSize * 0.5))
        NSGraphicsContext.restoreGraphicsState()

        let isJPG = Formats.norm(src.pathExtension) == "jpg"
        let props: [NSBitmapImageRep.PropertyKey: Any] = isJPG ? [.compressionFactor: Double(Prefs.imageQuality) / 100.0] : [:]
        guard let data = bmp.representation(using: isJPG ? .jpeg : .png, properties: props) else {
            throw ConvertError.msg("Не удалось сохранить картинку")
        }
        let o = out(src, "водяной знак", isJPG ? "jpg" : "png")
        try data.write(to: o)
        return o
    }

    private static func compressPDF(_ src: URL) throws -> URL {
        guard let d = PDFDocument(url: src) else { throw ConvertError.msg("Не удалось открыть PDF") }
        let o = out(src, "сжато", "pdf")
        let options: [PDFDocumentWriteOption: Any] = [
            .saveImagesAsJPEGOption: true,
            .optimizeImagesForScreenOption: true
        ]
        guard d.write(to: o, withOptions: options) else { throw ConvertError.msg("Не удалось сохранить PDF") }
        return o
    }

    private static func passwordPDF(_ src: URL, _ password: String) throws -> URL {
        guard let d = PDFDocument(url: src) else { throw ConvertError.msg("Не удалось открыть PDF") }
        let o = out(src, "с паролем", "pdf")
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: password,
            .ownerPasswordOption: password
        ]
        guard d.write(to: o, withOptions: options) else { throw ConvertError.msg("Не удалось сохранить PDF") }
        return o
    }

    // MARK: распознавание текста
    private static func ocr(_ src: URL) async throws -> URL {
        let text: String = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let img = NSImage(contentsOf: src),
                      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    cont.resume(throwing: ConvertError.msg("Не удалось открыть картинку"))
                    return
                }
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.recognitionLanguages = ["ru-RU", "en-US"]
                req.usesLanguageCorrection = true
                do {
                    try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
                    let found = req.results ?? []
                    let lines = found.compactMap { $0.topCandidates(1).first?.string }
                    cont.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        guard !text.isEmpty else { throw ConvertError.msg("Текст на картинке не найден") }
        let o = out(src, "текст", "txt")
        try text.write(to: o, atomically: true, encoding: .utf8)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return o
    }

    // MARK: документы
    private static func toTarget(_ u: URL, _ target: String) async throws -> URL {
        let e = Formats.norm(u.pathExtension)
        guard let k = Formats.kind(of: e) else { throw ConvertError.msg("Формат не поддерживается") }
        return try await Converter.convert(u, kind: k, ext: e, target: target, keepOriginal: true) { _ in }
    }

    private static func mergeDocsToPDF(_ urls: [URL]) async throws -> URL {
        var pdfs: [URL] = []
        var temp: [URL] = []
        for u in sorted(urls) {
            if Formats.norm(u.pathExtension) == "pdf" {
                pdfs.append(u)
            } else {
                let p = try await toTarget(u, "pdf")
                pdfs.append(p)
                temp.append(p)
            }
        }
        defer { for t in temp { try? FileManager.default.removeItem(at: t) } }
        return try mergePDF(pdfs)
    }

    // MARK: PDF
    private static func mergePDF(_ urls: [URL]) throws -> URL {
        let files = sorted(urls)
        let doc = PDFDocument()
        var idx = 0
        for u in files {
            guard let d = PDFDocument(url: u) else { throw ConvertError.msg("Не удалось открыть \(u.lastPathComponent)") }
            for i in 0..<d.pageCount {
                if let p = d.page(at: i)?.copy() as? PDFPage {
                    doc.insert(p, at: idx)
                    idx += 1
                }
            }
        }
        let o = out(files[0], "объединено", "pdf")
        guard doc.write(to: o) else { throw ConvertError.msg("Не удалось сохранить PDF") }
        return o
    }

    private static func splitPDF(_ src: URL) throws -> [URL] {
        guard let d = PDFDocument(url: src) else { throw ConvertError.msg("Не удалось открыть PDF") }
        var outs: [URL] = []
        for i in 0..<d.pageCount {
            guard let p = d.page(at: i)?.copy() as? PDFPage else { continue }
            let one = PDFDocument()
            one.insert(p, at: 0)
            let o = out(src, "стр. \(i + 1)", "pdf")
            if one.write(to: o) { outs.append(o) }
        }
        if outs.isEmpty { throw ConvertError.msg("Не удалось разделить PDF") }
        return outs
    }

    private static func rotatePDF(_ src: URL) throws -> URL {
        guard let d = PDFDocument(url: src) else { throw ConvertError.msg("Не удалось открыть PDF") }
        for i in 0..<d.pageCount {
            if let p = d.page(at: i) { p.rotation = (p.rotation + 90) % 360 }
        }
        let o = out(src, "повернуто", "pdf")
        guard d.write(to: o) else { throw ConvertError.msg("Не удалось сохранить PDF") }
        return o
    }

    // MARK: диалог «Обрезать»
    private static func askRange(duration: Double?) async -> (Double, Double)? {
        var message = "Время в секундах или мм:сс, например 0:15 и 1:30. Пустой конец значит «до конца»."
        var startText = "0:00"
        var endText = duration.map { formatTime($0) } ?? ""

        while true {
            let fields = [DialogField(label: "Начало:", value: startText),
                          DialogField(label: "Конец:", value: endText)]
            guard let r = await Dialogs.show(title: "Обрезать", message: message, fields: fields, buttons: ["Обрезать"]) else {
                return nil
            }
            startText = r.values[0]
            endText = r.values[1]
            let startEmpty = startText.trimmingCharacters(in: .whitespaces).isEmpty
            let endEmpty = endText.trimmingCharacters(in: .whitespaces).isEmpty

            let s: Double? = startEmpty ? 0 : parseTime(startText)
            let e: Double? = endEmpty ? duration : parseTime(endText)
            guard let sv = s else { message = "Не понял «Начало». Пример: 0:15"; continue }
            guard let ev = e else {
                message = endEmpty ? "Укажи «Конец», например 1:30" : "Не понял «Конец». Пример: 1:30"
                continue
            }
            guard ev > sv else {
                message = "Конец (\(formatTime(ev))) должен быть позже начала (\(formatTime(sv)))"
                continue
            }
            return (sv, ev)
        }
    }

    private static func formatTime(_ t: Double) -> String {
        let total = Int(t.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private static func parseTime(_ text: String) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }
}
