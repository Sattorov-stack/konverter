import AppKit

/// Колесо действий (Control): копировать, отправить, заархивировать и т.д.
@MainActor
enum Actions {
    static let items: [WheelItem] = [
        WheelItem(id: "copy", title: "Копия", symbol: "doc.on.doc"),
        WheelItem(id: "path", title: "Путь", symbol: "link"),
        WheelItem(id: "airdrop", title: "AirDrop", symbol: "dot.radiowaves.left.and.right"),
        WheelItem(id: "mail", title: "Почта", symbol: "envelope"),
        WheelItem(id: "message", title: "Сообщ.", symbol: "message"),
        WheelItem(id: "zip", title: "ZIP", symbol: "archivebox"),
        WheelItem(id: "duplicate", title: "Дубль", symbol: "plus.square.on.square"),
        WheelItem(id: "desktop", title: "На стол", symbol: "desktopcomputer"),
        WheelItem(id: "rename", title: "Имя", symbol: "pencil"),
        WheelItem(id: "move", title: "В папку", symbol: "folder.badge.plus")
    ]

    static func run(_ id: String, _ urls: [URL]) {
        let toast = ToastController.shared
        let pb = NSPasteboard.general
        let label = urls.count == 1 ? urls[0].lastPathComponent : "Файлов: \(urls.count)"

        switch id {
        case "copy":
            pb.clearContents()
            pb.writeObjects(urls as [NSURL])
            toast.note("Скопировано", "Вставь куда нужно: ⌘V")
        case "path":
            pb.clearContents()
            pb.setString(urls.map { $0.path }.joined(separator: "\n"), forType: .string)
            toast.note("Путь скопирован", label)
        case "airdrop":
            share(.sendViaAirDrop, urls)
        case "mail":
            share(.composeEmail, urls)
        case "message":
            share(.composeMessage, urls)
        case "zip":
            archive(urls, label: label)
        case "duplicate":
            duplicate(urls)
        case "desktop":
            toDesktop(urls)
        case "rename":
            Task { await rename(urls) }
        case "move":
            Task { await move(urls) }
        default:
            break
        }
    }

    private static func share(_ name: NSSharingService.Name, _ urls: [URL]) {
        guard let service = NSSharingService(named: name), service.canPerform(withItems: urls) else {
            ToastController.shared.info("Недоступно", "Не удалось открыть отправку")
            return
        }
        service.perform(withItems: urls)
    }

    private static func archive(_ urls: [URL], label: String) {
        guard let first = urls.first else { return }
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Архив"
        let o = Converter.uniqueOut(dir: first.deletingLastPathComponent(), base: base, ext: "zip")
        ToastController.shared.run("Архивирую…", label) {
            if urls.count == 1 {
                try await Converter.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, o.path])
            } else {
                try await Converter.run("/usr/bin/zip", ["-q", "-j", o.path] + urls.map { $0.path })
            }
            return [o]
        }
    }

    private static func rename(_ urls: [URL]) async {
        guard let first = urls.first else { return }
        let base0 = first.deletingPathExtension().lastPathComponent
        guard let template = await Dialogs.askText(
            title: "Переименовать",
            message: "Шаблон: {имя} старое имя, {n} номер, {дата} сегодняшняя дата. Расширение сохранится.",
            defaultValue: urls.count > 1 ? "{имя} {n}" : base0) else { return }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())

        var done: [URL] = []
        for (i, u) in urls.enumerated() {
            let old = u.deletingPathExtension().lastPathComponent
            var name = template
                .replacingOccurrences(of: "{имя}", with: old)
                .replacingOccurrences(of: "{n}", with: String(i + 1))
                .replacingOccurrences(of: "{дата}", with: today)
            if urls.count > 1 && !template.contains("{n}") { name += " \(i + 1)" }
            name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let dir = u.deletingLastPathComponent()
            let same = dir.appendingPathComponent(u.pathExtension.isEmpty ? name : "\(name).\(u.pathExtension)")
            if same.path == u.path { done.append(u); continue }   // имя не изменилось
            let dest = Converter.uniqueOut(dir: dir, base: name, ext: u.pathExtension)
            if (try? FileManager.default.moveItem(at: u, to: dest)) != nil { done.append(dest) }
        }
        report(done, ok: "Переименовано", fail: "Не удалось переименовать")
    }

    private static func move(_ urls: [URL]) async {
        let fm = FileManager.default
        let places: [(String, FileManager.SearchPathDirectory)] = [
            ("Рабочий стол", .desktopDirectory), ("Документы", .documentDirectory),
            ("Загрузки", .downloadsDirectory), ("Изображения", .picturesDirectory),
            ("Фильмы", .moviesDirectory), ("Музыка", .musicDirectory)
        ]
        var titles = places.map { $0.0 }
        titles.append("Другая папка…")
        let what = urls.count == 1 ? urls[0].lastPathComponent : "Файлов: \(urls.count)"
        guard let r = await Dialogs.show(title: "Переместить в…", message: what, buttons: titles, vertical: true) else { return }

        var folder: URL?
        if r.button < places.count {
            folder = fm.urls(for: places[r.button].1, in: .userDomainMask).first
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Переместить сюда"
            NSApp.activate(ignoringOtherApps: true)
            panel.level = .floating
            if panel.runModal() == .OK { folder = panel.url }
        }
        guard let dest = folder else { return }

        var done: [URL] = []
        for u in urls {
            if u.deletingLastPathComponent().standardizedFileURL.path == dest.standardizedFileURL.path { done.append(u); continue }  // уже в этой папке
            let target = Converter.uniqueOut(dir: dest, base: u.deletingPathExtension().lastPathComponent, ext: u.pathExtension)
            if (try? fm.moveItem(at: u, to: target)) != nil { done.append(target) }
        }
        report(done, ok: "Перемещено", fail: "Не удалось переместить")
    }

    private static func duplicate(_ urls: [URL]) {
        var done: [URL] = []
        for u in urls {
            let base = u.deletingPathExtension().lastPathComponent + " копия"
            let dest = Converter.uniqueOut(dir: u.deletingLastPathComponent(), base: base, ext: u.pathExtension)
            if (try? FileManager.default.copyItem(at: u, to: dest)) != nil { done.append(dest) }
        }
        report(done, ok: "Копия создана", fail: "Не удалось создать копию")
    }

    private static func report(_ done: [URL], ok: String, fail: String) {
        if done.isEmpty {
            ToastController.shared.info(fail, "Проверь права доступа к папке")
        } else {
            ToastController.shared.note(ok, done.count == 1 ? done[0].lastPathComponent : "Файлов: \(done.count)")
        }
    }

    private static func toDesktop(_ urls: [URL]) {
        let fm = FileManager.default
        guard let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
        var done: [URL] = []
        for u in urls {
            var dest = desktop.appendingPathComponent(u.lastPathComponent)
            var i = 1
            while fm.fileExists(atPath: dest.path) {
                let ext = u.pathExtension
                let base = u.deletingPathExtension().lastPathComponent
                dest = desktop.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
                i += 1
            }
            if (try? fm.copyItem(at: u, to: dest)) != nil { done.append(dest) }
        }
        if done.isEmpty {
            ToastController.shared.info("Не получилось", "Не удалось скопировать на рабочий стол")
        } else {
            ToastController.shared.note("На рабочем столе", done.count == 1 ? done[0].lastPathComponent : "Файлов: \(done.count)")
        }
    }
}
