import SwiftUI
import AppKit

enum WheelMode { case convert, tools, actions }

struct WheelItem: Identifiable {
    let id: String
    let title: String
    var symbol: String? = nil
}

/// Какой сегмент сейчас под курсором (общее состояние для AppKit-приёмника и SwiftUI-рисунка)
final class WheelState: ObservableObject {
    @Published var hover: Int?
}

enum WheelGeometry {
    static let inner: CGFloat = 38
    static let panel: CGFloat = 280
    static func outer(count: Int) -> CGFloat { count > 8 ? 132 : 120 }
}

// MARK: приёмник перетаскивания (нативный AppKit, надёжнее SwiftUI onDrop)
final class WheelDropView: NSView {
    var ids: [String] = []
    var outer: CGFloat = 120
    var state: WheelState?
    var onPick: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func index(_ sender: NSDraggingInfo) -> Int? {
        let p = convert(sender.draggingLocation, from: nil)
        let dx = Double(p.x - bounds.width / 2)
        let dy = Double(bounds.height / 2 - p.y)
        let r = hypot(dx, dy)
        guard !ids.isEmpty, r >= Double(WheelGeometry.inner), r <= Double(outer) else { return nil }
        var deg = atan2(dy, dx) * 180 / Double.pi + 90
        if deg < 0 { deg += 360 }
        let sector = 360.0 / Double(ids.count)
        return min(ids.count - 1, Int(deg / sector))
    }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        let i = index(sender)
        state?.hover = i
        return i == nil ? [] : .generic
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { state?.hover = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { index(sender) != nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let i = index(sender) else { return false }
        state?.hover = nil
        Log.write("Файл брошен на сегмент: \(ids[i])")
        onPick?(ids[i])
        return true
    }
}

// MARK: окно с колесом
@MainActor
final class WheelController {
    private var panel: NSPanel?
    private var urls: [URL] = []
    private var mode: WheelMode = .convert
    var onFinished: (() -> Void)?
    var isVisible: Bool { panel?.isVisible ?? false }

    static func convertItems(_ urls: [URL]) -> [WheelItem] {
        let supported = urls.compactMap { u -> (Kind, String)? in
            let e = Formats.norm(u.pathExtension)
            guard let k = Formats.kind(of: e) else { return nil }
            return (k, e)
        }
        guard let first = supported.first else { return [] }
        // варианты, общие для всех файлов; если общих нет, берём варианты первого
        var options = first.0.wheel.filter { $0 != first.1 }
        for s in supported.dropFirst() {
            options = options.filter { s.0.outputs.contains($0) && $0 != s.1 }
        }
        if options.isEmpty { options = first.0.wheel.filter { $0 != first.1 } }
        return options.map { WheelItem(id: $0, title: $0.uppercased()) }
    }

    func show(for urls: [URL], mode: WheelMode) {
        // папки раскрываем в файлы (для «Действий» оставляем как есть, чтобы можно было, например, заархивировать папку)
        let urls = mode == .actions ? urls : Expand.files(urls)
        let list: [WheelItem]
        switch mode {
        case .convert: list = Self.convertItems(urls)
        case .tools: list = Tools.items(for: urls)
        case .actions: list = Actions.items
        }
        guard !list.isEmpty else {
            Log.write("Для \(urls.first?.lastPathComponent ?? "?") нет вариантов на колесе (\(mode))")
            ToastController.shared.info("Для этого файла пока нет вариантов", urls.first?.lastPathComponent ?? "")
            return
        }
        Log.write("Колесо \(mode): пунктов \(list.count), файлов \(urls.count)")

        self.urls = urls
        self.mode = mode
        hide()

        let size = WheelGeometry.panel
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        let state = WheelState()

        let hosting = NSHostingView(rootView: WheelView(items: list, state: state, size: size))
        hosting.frame = frame

        let drop = WheelDropView(frame: frame)
        drop.ids = list.map { $0.id }
        drop.outer = WheelGeometry.outer(count: list.count)
        drop.state = state
        drop.onPick = { [weak self] id in self?.picked(id) }

        let container = NSView(frame: frame)
        container.addSubview(hosting)
        container.addSubview(drop) // сверху, чтобы именно он принимал файл

        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.contentView = container

        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - size / 2, y: mouse.y - size / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX), f.maxX - size)
            origin.y = min(max(origin.y, f.minY), f.maxY - size)
        }
        p.setFrameOrigin(origin)
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Прячет колесо с задержкой: система должна успеть доставить файл на сегмент
    func hide(after delay: TimeInterval) {
        guard let current = panel else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if let self = self, self.panel === current { self.hide() }
        }
    }

    private func picked(_ id: String) {
        let files = urls
        let m = mode
        // закрываем колесо уже после того, как система завершит перетаскивание
        DispatchQueue.main.async { [weak self] in
            self?.hide()
            self?.onFinished?()
            switch m {
            case .convert: ToastController.shared.convert(files, to: id)
            case .tools: Tools.run(id, files)
            case .actions: Actions.run(id, files)
            }
        }
    }
}

// MARK: вид колеса (тёмное стекло)
struct WheelView: View {
    let items: [WheelItem]
    @ObservedObject var state: WheelState
    let size: CGFloat

    private var inner: CGFloat { WheelGeometry.inner }
    private var outer: CGFloat { WheelGeometry.outer(count: items.count) }

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .frame(width: outer * 2 + 10, height: outer * 2 + 10)

            ForEach(items.indices, id: \.self) { i in
                Sector(index: i, count: items.count, inner: inner, outer: outer)
                    .fill(state.hover == i ? tangerine : Color.black.opacity(0.42))
                Sector(index: i, count: items.count, inner: inner, outer: outer)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                label(i)
            }

            Circle()
                .fill(Color.black.opacity(0.28))
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .frame(width: inner * 2 - 8, height: inner * 2 - 8)
        }
        .frame(width: size, height: size)
    }

    private func label(_ i: Int) -> some View {
        let item = items[i]
        return VStack(spacing: 2) {
            if let s = item.symbol {
                Image(systemName: s).font(.system(size: 15, weight: .semibold))
            }
            Text(item.title)
                .font(.system(size: item.symbol == nil ? 12.5 : 10.5, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Color.white)
        .offset(labelOffset(i))
    }

    private func labelOffset(_ i: Int) -> CGSize {
        let step = 2 * Double.pi / Double(items.count)
        let a = -Double.pi / 2 + (Double(i) + 0.5) * step
        let r = Double(inner + outer) / 2
        return CGSize(width: r * cos(a), height: r * sin(a))
    }
}

struct Sector: Shape {
    let index: Int
    let count: Int
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let step = 2 * Double.pi / Double(count)
        let gap = 0.035
        let a0 = -Double.pi / 2 + Double(index) * step + gap
        let a1 = -Double.pi / 2 + Double(index + 1) * step - gap
        let n = max(4, Int((a1 - a0) / 0.05))
        var p = Path()
        for k in 0...n {
            let a = a0 + (a1 - a0) * Double(k) / Double(n)
            let pt = CGPoint(x: c.x + outer * CGFloat(cos(a)), y: c.y + outer * CGFloat(sin(a)))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        for k in stride(from: n, through: 0, by: -1) {
            let a = a0 + (a1 - a0) * Double(k) / Double(n)
            p.addLine(to: CGPoint(x: c.x + inner * CGFloat(cos(a)), y: c.y + inner * CGFloat(sin(a))))
        }
        p.closeSubpath()
        return p
    }
}
