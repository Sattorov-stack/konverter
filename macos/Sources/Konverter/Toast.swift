import SwiftUI
import AppKit

// MARK: небольшая плашка с прогрессом и результатом
@MainActor
final class ToastModel: ObservableObject {
    enum State { case working, done, failed }
    @Published var state: State = .working
    @Published var title = ""
    @Published var detail = ""
    @Published var reveal: [URL] = []
}

@MainActor
final class ToastController {
    static let shared = ToastController()
    private let model = ToastModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func info(_ title: String, _ detail: String) {
        present(.failed, title, detail, [])
        autoHide(3)
    }

    /// Показывает плашку «в процессе» с нужным текстом (например, пока качается модель)
    func progress(_ title: String, _ detail: String) {
        present(.working, title, detail, [])
    }

    func note(_ title: String, _ detail: String) {
        present(.done, title, detail, [])
        autoHide(3)
    }

    /// Запускает любую работу и показывает плашку: прогресс, результат или ошибку
    func run(_ title: String, _ detail: String, work: @escaping () async throws -> [URL]) {
        present(.working, title, detail, [])
        Task {
            do {
                let outs = try await work()
                present(.done, "Готово",
                        outs.count == 1 ? outs[0].lastPathComponent : "Файлов: \(outs.count)", outs)
                autoHide(5)
                Notifier.finished("Готово", outs.count == 1 ? outs[0].lastPathComponent : "Файлов: \(outs.count)", ok: true)
            } catch {
                Log.write("ОШИБКА \(title): \(error.localizedDescription)")
                present(.failed, "Ошибка", error.localizedDescription, [])
                autoHide(9)
                Notifier.finished("Ошибка", error.localizedDescription, ok: false)
            }
        }
    }

    func convert(_ urls: [URL], to target: String) {
        let files = urls.compactMap { u -> (URL, Kind, String)? in
            let e = Formats.norm(u.pathExtension)
            guard let k = Formats.kind(of: e), k.outputs.contains(target), e != target else { return nil }
            return (u, k, e)
        }
        guard !files.isEmpty else {
            info("Не получилось", "Эти файлы нельзя превратить в \(target.uppercased())")
            return
        }
        present(.working, "Конвертирую в \(target.uppercased())…",
                files.count > 1 ? "Файлов: \(files.count)" : files[0].0.lastPathComponent, [])

        Task {
            var outs: [URL] = []
            var errors: [String] = []
            for (i, f) in files.enumerated() {
                if files.count > 1 { model.detail = "\(i + 1) из \(files.count): \(f.0.lastPathComponent)" }
                do {
                    let out = try await Converter.convert(f.0, kind: f.1, ext: f.2, target: target) { _ in }
                    outs.append(out)
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
            if let e = errors.first { Log.write("ОШИБКА конвертации: \(e)") }
            if errors.isEmpty {
                present(.done, "Готово", outs.count == 1 ? outs[0].lastPathComponent : "Сохранено файлов: \(outs.count)", outs)
                autoHide(5)
                Notifier.finished("Готово", outs.count == 1 ? outs[0].lastPathComponent : "Сохранено файлов: \(outs.count)", ok: true)
            } else {
                present(.failed, "Ошибка", errors[0], outs)
                autoHide(9)
                Notifier.finished("Ошибка", errors[0], ok: false)
            }
        }
    }

    private func present(_ state: ToastModel.State, _ title: String, _ detail: String, _ reveal: [URL]) {
        hideTask?.cancel()
        model.state = state
        model.title = title
        model.detail = detail
        model.reveal = reveal
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 78),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: ToastView(model: model))
            panel = p
        }
        if let p = panel {
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: f.midX - 170, y: f.maxY - 98))
            }
            p.orderFrontRegardless()
        }
    }

    private func autoHide(_ seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }
}

struct ToastView: View {
    @ObservedObject var model: ToastModel

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).fontWeight(.semibold)
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if !model.reveal.isEmpty {
                Button("Показать") { NSWorkspace.shared.activateFileViewerSelecting(model.reveal) }
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 340, height: 78)
        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .working:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange)
        }
    }
}
