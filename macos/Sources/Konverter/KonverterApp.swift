import SwiftUI
import AppKit
import UniformTypeIdentifiers

let tangerine = Color(red: 0.94, green: 0.45, blue: 0.04)

@main
struct KonverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Конвертер", id: "main") {
            ContentView().tint(tangerine)
        }
        .defaultSize(width: 680, height: 560)

        Settings {
            SettingsView()
        }

        MenuBarExtra("Конвертер", systemImage: "arrow.triangle.2.circlepath") {
            MenuContent()
        }
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Открыть окно") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            raiseLater()
        }
        Button("Настройки…") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            raiseLater()
        }
        Text("Тащи файл и нажми кнопку: появится колесо")
        Divider()
        Button("Выйти") { NSApp.terminate(nil) }
    }

    /// Окно могло открыться позади Finder: чуть позже поднимаем его наверх
    private func raiseLater() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            Dialogs.raiseAppWindows()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var watcher: DragWatcher?
    private var folderWatcher: FolderWatcher?
    private let services = ServiceProvider()
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // не даём macOS «усыплять» приложение, пока оно следит за перетаскиванием
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Отслеживание перетаскивания файлов")
        Notifier.setup()
        watcher = DragWatcher()
        watcher?.start()
        folderWatcher = FolderWatcher()
        folderWatcher?.start()
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    // закрыл окно, а колесо при перетаскивании продолжает работать
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct ContentView: View {
    @StateObject private var store = Store()
    @State private var over = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    dropZone
                    ForEach(store.items) { item in
                        RowView(item: item, store: store)
                    }
                }
                .padding(20)
            }
            if !store.items.isEmpty {
                Divider()
                footer
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .onDrop(of: [UTType.fileURL], isTargeted: $over) { providers in
            handleDrop(providers)
            return true
        }
        .onOpenURL { url in store.add([url]) }
        .alert("Этот формат пока не поддерживается", isPresented: $store.showRejected) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.rejected)
        }
    }

    private var dropZone: some View {
        let compact = !store.items.isEmpty
        return VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: compact ? 18 : 34))
                .foregroundStyle(over ? tangerine : .secondary)
            Text(compact ? "Добавить ещё файлы" : "Перетащи файлы сюда")
                .font(compact ? .callout.weight(.semibold) : .title3.weight(.semibold))
            if !compact {
                Text("Фото, музыка, видео и документы. Оригинал останется, новый файл появится рядом.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 14 : 44)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(over ? tangerine : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        )
        .contentShape(Rectangle())
        .onTapGesture { pick() }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Menu("Все в…") {
                ForEach(store.commonTargets, id: \.self) { t in
                    Button(t.uppercased()) { store.setAll(t) }
                }
            }
            .frame(width: 90)
            .disabled(store.busy)

            Text("Файлов: \(store.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Очистить") { store.clear() }
                .disabled(store.busy)
            Button(store.busy ? "Конвертирую…" : "Конвертировать") { store.convertAll() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(store.busy || !store.hasWork)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { store.add(panel.urls) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                if let d = data as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) {
                    lock.lock(); urls.append(u); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            lock.lock(); let all = urls; lock.unlock()
            store.add(all)
        }
    }
}

struct RowView: View {
    @ObservedObject var item: Item
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.icon)
                .font(.title2)
                .foregroundStyle(tangerine)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusView
            }
            Spacer(minLength: 8)
            Picker("", selection: $item.target) {
                ForEach(item.options, id: \.self) { Text($0.uppercased()).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
            .disabled(store.busy)
            Button { store.remove(item) } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.busy)
            .help("Убрать из списка")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
        .onChange(of: item.target) { _ in
            if item.status != .idle && item.status != .working { item.status = .idle }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .idle:
            Text(item.ext.uppercased()).font(.caption).foregroundStyle(.secondary)
        case .working:
            if item.progress > 0 {
                ProgressView(value: item.progress).progressViewStyle(.linear)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        case .done:
            HStack(spacing: 8) {
                Text("Готово").fontWeight(.semibold).foregroundStyle(.green)
                Button("Показать в Finder") {
                    if let o = item.output { NSWorkspace.shared.activateFileViewerSelecting([o]) }
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(3)
        }
    }
}
