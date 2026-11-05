import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Основные", systemImage: "gearshape") }
            QualitySettings()
                .tabItem { Label("Качество", systemImage: "slider.horizontal.3") }
            WheelSettings()
                .tabItem { Label("Колесо форматов", systemImage: "circle.grid.3x3") }
            WatchSettings()
                .tabItem { Label("Папки", systemImage: "folder.badge.gearshape") }
        }
        .frame(width: 560, height: 500)
        .tint(tangerine)
    }
}

// MARK: основные
struct GeneralSettings: View {
    @AppStorage("modConvert") private var modConvert = "shift"
    @AppStorage("modTools") private var modTools = "command"
    @AppStorage("modActions") private var modActions = "control"
    @AppStorage("saveMode") private var saveMode = 0
    @AppStorage("outputFolder") private var outputFolder = ""
    @AppStorage("trashOriginal") private var trashOriginal = false
    @AppStorage("notify") private var notify = true
    @AppStorage("sound") private var sound = true
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""

    private var duplicate: Bool {
        let used = [modConvert, modTools, modActions].filter { $0 != "off" }
        return Set(used).count != used.count
    }

    var body: some View {
        Form {
            Section("Колёса при перетаскивании файла") {
                modPicker("Смена формата", $modConvert)
                modPicker("Инструменты", $modTools)
                modPicker("Действия", $modActions)
                Text("Начни тащить файл и нажми выбранную кнопку.")
                    .font(.caption).foregroundStyle(.secondary)
                if duplicate {
                    Text("Одна и та же кнопка выбрана для двух колёс: сработает только первое.")
                        .font(.caption).foregroundStyle(.red)
                }
            }

            Section("Куда сохранять") {
                Picker("Результат", selection: $saveMode) {
                    Text("Рядом с оригиналом").tag(0)
                    Text("В подпапку Converted").tag(1)
                    Text("В выбранную папку").tag(2)
                }
                if saveMode == 2 {
                    HStack {
                        Text(outputFolder.isEmpty ? "Папка не выбрана" : outputFolder)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Выбрать…") { chooseFolder() }
                    }
                }
                Toggle("После конвертации переносить оригинал в корзину", isOn: $trashOriginal)
            }

            Section("Система") {
                Toggle("Запускать при входе в систему", isOn: $loginOn)
                    .onChange(of: loginOn) { value in setLogin(value) }
                if !loginError.isEmpty {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Уведомления", isOn: $notify)
                Toggle("Звук по завершении", isOn: $sound)
            }
        }
        .formStyle(.grouped)
    }

    private func modPicker(_ title: String, _ binding: Binding<String>) -> some View {
        Picker(title, selection: binding) {
            Text("Shift").tag("shift")
            Text("Command").tag("command")
            Text("Control").tag("control")
            Text("Option").tag("option")
            Text("Выключено").tag("off")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Выбрать"
        if panel.runModal() == .OK, let url = panel.url { outputFolder = url.path }
    }

    private func setLogin(_ on: Bool) {
        guard (SMAppService.mainApp.status == .enabled) != on else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = ""
        } catch {
            loginError = "Не получилось: \(error.localizedDescription). Положи приложение в «Программы» и попробуй снова."
            loginOn = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: качество
struct QualitySettings: View {
    @AppStorage("imageQuality") private var imageQuality = 90
    @AppStorage("imageMaxSide") private var imageMaxSide = 0
    @AppStorage("audioBitrate") private var audioBitrate = 192
    @AppStorage("videoQuality") private var videoQuality = 1
    @AppStorage("videoMaxHeight") private var videoMaxHeight = 0

    var body: some View {
        Form {
            Section("Фото") {
                VStack(alignment: .leading) {
                    Text("Качество JPG, HEIC, WEBP: \(imageQuality)%")
                    Slider(value: Binding(get: { Double(imageQuality) }, set: { imageQuality = Int($0) }),
                           in: 40...100, step: 5)
                }
                Picker("Максимальная сторона", selection: $imageMaxSide) {
                    Text("Как у оригинала").tag(0)
                    Text("4096 px").tag(4096)
                    Text("2560 px").tag(2560)
                    Text("1920 px").tag(1920)
                    Text("1280 px").tag(1280)
                    Text("1024 px").tag(1024)
                }
            }
            Section("Музыка") {
                Picker("Битрейт MP3, M4A, OGG, OPUS", selection: $audioBitrate) {
                    Text("128 кбит/с").tag(128)
                    Text("160 кбит/с").tag(160)
                    Text("192 кбит/с").tag(192)
                    Text("256 кбит/с").tag(256)
                    Text("320 кбит/с").tag(320)
                }
            }
            Section("Видео") {
                Picker("Качество", selection: $videoQuality) {
                    Text("Высокое (файл больше)").tag(0)
                    Text("Среднее").tag(1)
                    Text("Малое (файл меньше)").tag(2)
                }
                Picker("Максимальная высота", selection: $videoMaxHeight) {
                    Text("Как у оригинала").tag(0)
                    Text("2160 px (4K)").tag(2160)
                    Text("1440 px").tag(1440)
                    Text("1080 px").tag(1080)
                    Text("720 px").tag(720)
                    Text("480 px").tag(480)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: свои колёса форматов
struct WheelSettings: View {
    @State private var kind: Kind = .image
    @State private var order: [String] = []
    @State private var hidden: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Тип файла", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Галочка значит «показывать на колесе». Тяни строки, чтобы поменять порядок: верхние идут первыми.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(order, id: \.self) { f in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { !hidden.contains(f) },
                            set: { on in
                                if on { hidden.remove(f) } else { hidden.insert(f) }
                                save()
                            })) {
                            Text(f.uppercased()).fontWeight(.semibold)
                        }
                        Spacer()
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                    }
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    save()
                }
            }

            HStack {
                Spacer()
                Button("Сбросить") {
                    Prefs.resetWheel(kind)
                    load()
                }
            }
        }
        .padding()
        .onAppear { load() }
        .onChange(of: kind) { _ in load() }
    }

    private func load() {
        let s = Prefs.wheelState(kind)
        order = s.order
        hidden = s.hidden
    }

    private func save() {
        Prefs.saveWheel(kind, order: order, hidden: hidden)
    }
}

// MARK: папки-наблюдатели
struct WatchSettings: View {
    @AppStorage("watchEnabled") private var enabled = false
    @State private var rules: [WatchRule] = Prefs.watchRules

    var body: some View {
        Form {
            Section {
                Toggle("Следить за папками", isOn: $enabled)
                Text("Новый файл в выбранной папке сам превратится в нужный формат. Результат попадёт в подпапку «Готово», оригинал останется. Файлы, которые уже лежали в папке, не трогаются.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($rules) { $rule in
                Section {
                    HStack {
                        Text(rule.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Убрать") { rules.removeAll { $0.id == rule.id } }
                    }
                    formatPicker("Фото в", $rule.image, Kind.image.outputs)
                    formatPicker("Музыка в", $rule.audio, Kind.audio.outputs)
                    formatPicker("Видео в", $rule.video, Kind.video.outputs)
                    formatPicker("Документы в", $rule.doc, Kind.doc.outputs)
                }
            }
            Button("Добавить папку…") { addFolder() }
        }
        .formStyle(.grouped)
        .onChange(of: rules) { _ in Prefs.saveWatchRules(rules) }
    }

    private func formatPicker(_ title: String, _ binding: Binding<String>, _ formats: [String]) -> some View {
        Picker(title, selection: binding) {
            Text("ничего").tag("")
            ForEach(formats, id: \.self) { Text($0.uppercased()).tag($0) }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Следить"
        if panel.runModal() == .OK, let url = panel.url, !rules.contains(where: { $0.path == url.path }) {
            rules.append(WatchRule(path: url.path))
        }
    }
}
