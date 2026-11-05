import AppKit

/// Пункт «Конвертер…» в правом клике Finder (меню «Службы» / «Быстрые действия»)
final class ServiceProvider: NSObject {
    @objc func convertFiles(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let objs = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let urls = (objs as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        Task { @MainActor in await ContextMenu.handle(urls) }
    }
}

@MainActor
enum ContextMenu {
    static func handle(_ files: [URL]) async {
        let what = files.count == 1 ? files[0].lastPathComponent : "Файлов: \(files.count)"
        guard let m = await Dialogs.show(title: "Конвертер", message: what,
                                         buttons: ["Сменить формат…", "Инструменты…", "Действия…"], vertical: true) else { return }
        let mode: WheelMode = [WheelMode.convert, .tools, .actions][m.button]
        let all = mode == .actions ? files : Expand.files(files)

        let list: [WheelItem]
        switch mode {
        case .convert: list = WheelController.convertItems(all)
        case .tools: list = Tools.items(for: all)
        case .actions: list = Actions.items
        }
        guard !list.isEmpty else {
            ToastController.shared.info("Для этого файла пока нет вариантов", files[0].lastPathComponent)
            return
        }
        let title = ["Во что превратить?", "Инструменты", "Действия"][m.button]
        guard let r = await Dialogs.show(title: title, message: "", buttons: list.map { $0.title }, vertical: true) else { return }
        let id = list[r.button].id
        switch mode {
        case .convert: ToastController.shared.convert(all, to: id)
        case .tools: Tools.run(id, all)
        case .actions: Actions.run(id, all)
        }
    }
}
