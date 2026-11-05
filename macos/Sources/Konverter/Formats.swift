import Foundation

enum Kind: CaseIterable {
    case image, audio, video, doc, sheet, slides, pdf

    var icon: String {
        switch self {
        case .image: return "photo"
        case .audio: return "music.note"
        case .video: return "film"
        case .doc: return "doc.text"
        case .sheet: return "tablecells"
        case .slides: return "rectangle.on.rectangle"
        case .pdf: return "doc.richtext"
        }
    }

    var inputs: [String] {
        switch self {
        case .image: return ["heic", "jpg", "png", "webp", "gif", "tiff", "bmp", "avif"]
        case .audio: return ["mp3", "wav", "flac", "aac", "m4a", "ogg", "opus", "aiff", "wma"]
        case .video: return ["mp4", "mov", "mkv", "avi", "webm", "m4v", "flv", "wmv", "mpg"]
        case .doc: return ["doc", "docx", "odt", "rtf", "txt", "html"]
        case .sheet: return ["xls", "xlsx", "ods", "csv"]
        case .slides: return ["ppt", "pptx", "odp"]
        case .pdf: return ["pdf"]
        }
    }

    var outputs: [String] {
        switch self {
        case .image: return ["jpg", "png", "webp", "heic", "gif", "tiff", "bmp", "avif", "pdf"]
        case .audio: return ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"]
        case .video: return ["mp4", "mov", "mkv", "avi", "wmv", "webm", "gif", "mp3", "m4a", "wav"]
        case .doc: return ["pdf", "docx", "txt", "html", "epub", "png", "jpg", "odt", "rtf"]
        case .sheet: return ["pdf", "xlsx", "xls", "ods", "csv", "html"]
        case .slides: return ["pdf", "pptx", "ppt", "odp", "png", "jpg"]
        case .pdf: return ["docx", "txt", "jpg", "png"]
        }
    }

    var key: String {
        switch self {
        case .image: return "image"
        case .audio: return "audio"
        case .video: return "video"
        case .doc: return "doc"
        case .sheet: return "sheet"
        case .slides: return "slides"
        case .pdf: return "pdf"
        }
    }

    var title: String {
        switch self {
        case .image: return "Фото"
        case .audio: return "Музыка"
        case .video: return "Видео"
        case .doc: return "Документы"
        case .sheet: return "Таблицы"
        case .slides: return "Презентации"
        case .pdf: return "PDF"
        }
    }

    /// Что по умолчанию спрятано с колеса
    var defaultHidden: [String] {
        self == .video ? ["m4a", "wav"] : []
    }

    /// Что показываем на колесе (порядок и галочки задаются в настройках)
    var wheel: [String] {
        let s = Prefs.wheelState(self)
        return s.order.filter { !s.hidden.contains($0) }
    }

    var defaultTarget: String {
        switch self {
        case .image: return "jpg"
        case .audio: return "mp3"
        case .video: return "mp4"
        case .doc, .sheet, .slides: return "pdf"
        case .pdf: return "docx"
        }
    }
}

enum Formats {
    static let alias = ["jpeg": "jpg", "tif": "tiff", "htm": "html", "heif": "heic", "aif": "aiff", "mpeg": "mpg"]

    static func norm(_ ext: String) -> String {
        let e = ext.lowercased()
        return alias[e] ?? e
    }

    static func kind(of ext: String) -> Kind? {
        let e = norm(ext)
        return Kind.allCases.first { $0.inputs.contains(e) }
    }
}
