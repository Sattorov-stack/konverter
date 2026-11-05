import Foundation

/// Простой журнал: ~/Library/Logs/Konverter.log (помогает найти, что пошло не так)
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Konverter.log")

    static func write(_ text: String) {
        let line = "\(Date()) \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
