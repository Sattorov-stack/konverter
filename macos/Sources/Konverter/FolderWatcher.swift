import AppKit

struct WatchRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var path: String
    var image: String = "jpg"
    var audio: String = ""
    var video: String = ""
    var doc: String = ""
}

extension Prefs {
    static var watchEnabled: Bool { bool("watchEnabled", false) }

    static var watchRules: [WatchRule] {
        guard let s = UserDefaults.standard.string(forKey: "watchRules"),
              let data = s.data(using: .utf8),
              let rules = try? JSONDecoder().decode([WatchRule].self, from: data) else { return [] }
        return rules
    }

    static func saveWatchRules(_ rules: [WatchRule]) {
        guard let data = try? JSONEncoder().encode(rules), let s = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(s, forKey: "watchRules")
    }
}

/// Папки-наблюдатели: новый файл в выбранной папке сам конвертируется в нужный формат
@MainActor
final class FolderWatcher {
    private struct Entry {
        var size: Int
        var stable: Int
        var done: Bool
    }

    private var state: [String: [String: Entry]] = [:]
    private var busy = false
    private var timer: Timer?

    func start() {
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.scan() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func scan() async {
        guard !busy, Prefs.watchEnabled else { return }
        busy = true
        defer { busy = false }
        for rule in Prefs.watchRules { await scanRule(rule) }
    }

    private func scanRule(_ rule: WatchRule) async {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: rule.path, isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let first = state[rule.path] == nil
        var known = state[rule.path] ?? [:]
        var converted = 0
        var errors: [String] = []

        for name in names.sorted() where !name.hasPrefix(".") && !name.hasPrefix("~$") {
            let url = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0

            guard var st = known[name] else {
                // файлы, которые уже лежали при запуске, не трогаем
                known[name] = Entry(size: size, stable: 0, done: first)
                continue
            }
            if st.done { continue }
            if size == st.size && size > 0 { st.stable += 1 } else { st.size = size; st.stable = 0 }
            if st.stable < 1 { known[name] = st; continue }   // ждём, пока файл допишется
            st.done = true
            known[name] = st

            let ext = Formats.norm(url.pathExtension)
            guard let kind = Formats.kind(of: ext) else { continue }
            let target: String
            switch kind {
            case .image: target = rule.image
            case .audio: target = rule.audio
            case .video: target = rule.video
            case .doc: target = rule.doc
            default: target = ""
            }
            if target.isEmpty || target == ext { continue }
            do {
                _ = try await Converter.convert(url, kind: kind, ext: ext, target: target, keepOriginal: true,
                                                outDir: dir.appendingPathComponent("Готово"), progress: { _ in })
                converted += 1
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        }
        state[rule.path] = known

        let folder = dir.lastPathComponent
        if let e = errors.first {
            ToastController.shared.info("Папка «\(folder)»", e)
            Notifier.finished("Папка «\(folder)»", e, ok: false)
        } else if converted > 0 {
            let text = "Сконвертировано файлов: \(converted)"
            ToastController.shared.note("Папка «\(folder)»: готово", text)
            Notifier.finished("Папка «\(folder)»", text, ok: true)
        }
    }
}
