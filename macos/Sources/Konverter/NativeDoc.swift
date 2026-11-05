import AppKit
import PDFKit

/// Конвертация текстовых документов средствами самого macOS, без LibreOffice.
/// Умеет: DOC, DOCX, ODT, RTF, TXT, HTML → PDF, DOCX, ODT, RTF, TXT, HTML, PNG, JPG и PDF → TXT.
/// Если LibreOffice установлен, приложение использует его (качество вёрстки лучше).
@MainActor
enum NativeDoc {
    static func convert(src: URL, kind: Kind, target: String, out: URL) async throws {
        if kind == .pdf {
            guard let d = PDFDocument(url: src), let text = d.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConvertError.msg("В этом PDF нет текста (возможно, это скан)")
            }
            try text.write(to: out, atomically: true, encoding: .utf8)
            return
        }

        let attr = try load(src)
        let full = NSRange(location: 0, length: attr.length)

        switch target {
        case "txt":
            try attr.string.write(to: out, atomically: true, encoding: .utf8)
        case "rtf":
            try attr.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: out)
        case "html":
            try attr.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]).write(to: out)
        case "docx":
            try attr.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: out)
        case "odt":
            try attr.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.openDocument]).write(to: out)
        case "pdf":
            try makePDF(attr, to: out)
        case "png", "jpg":
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("konv-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try makePDF(attr, to: tmp)
            try await Converter.run("/usr/bin/sips", ["-s", "format", target == "jpg" ? "jpeg" : "png", tmp.path, "--out", out.path])
        default:
            throw ConvertError.msg(Converter.noOffice)
        }
    }

    private static func load(_ src: URL) throws -> NSAttributedString {
        if src.pathExtension.lowercased() == "txt" {
            var text: String
            if let t = try? String(contentsOf: src, encoding: .utf8) {
                text = t
            } else {
                text = try String(contentsOf: src, encoding: .windowsCP1251)
            }
            return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        }
        return try NSAttributedString(url: src, options: [:], documentAttributes: nil)
    }

    /// Печать в PDF с нормальной разбивкой на страницы A4
    private static func makePDF(_ attr: NSAttributedString, to out: URL) throws {
        let paper = NSSize(width: 595, height: 842)
        let margin: CGFloat = 56
        let width = paper.width - margin * 2

        let info = NSPrintInfo()
        info.paperSize = paper
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.jobDisposition = .save
        info.dictionary().setObject(out, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString)

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textStorage?.setAttributedString(attr)
        if let lm = tv.layoutManager, let tc = tv.textContainer {
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc)
            tv.frame = NSRect(x: 0, y: 0, width: width, height: max(used.height + 10, 100))
        }

        let op = NSPrintOperation(view: tv, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        _ = op.run()
        guard FileManager.default.fileExists(atPath: out.path) else {
            throw ConvertError.msg("Не удалось создать PDF")
        }
    }
}
