import AppKit

/// Следит за перетаскиванием файлов по всей системе.
/// Shift: колесо форматов. Command: инструменты. Control: действия.
@MainActor
final class DragWatcher {
    private var monitors: [Any] = []
    private var timer: Timer?
    private var downCount = 0
    private var dragging = false
    private var lastMode: WheelMode?
    private let wheel = WheelController()

    func start() {
        Log.write("Конвертер запущен, слежу за перетаскиванием")
        wheel.onFinished = { [weak self] in self?.stopDrag() }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            Task { @MainActor in self?.handle(type) }
        }) {
            monitors.append(m)
        }
    }

    private func handle(_ type: NSEvent.EventType) {
        let pb = NSPasteboard(name: .drag)
        switch type {
        case .leftMouseDown:
            downCount = pb.changeCount
            stopDrag()
            wheel.hide()
        case .leftMouseDragged:
            if !dragging, pb.changeCount != downCount, !Self.fileURLs(pb).isEmpty {
                dragging = true
                lastMode = nil
                Log.write("Началось перетаскивание файлов: \(Self.fileURLs(pb).count)")
                startPolling()
            }
        case .leftMouseUp:
            // Важно: колесо не прячем сразу, иначе система не успеет доставить файл на сегмент
            stopDrag()
            wheel.hide(after: 1.0)
        default:
            break
        }
    }

    private func startPolling() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func currentMode() -> WheelMode? {
        let f = NSEvent.modifierFlags.intersection([.shift, .command, .control, .option])
        for mode in [WheelMode.convert, .tools, .actions] {
            if let m = Prefs.modifier(for: mode), f == m { return mode }
        }
        return nil
    }

    private func tick() {
        guard dragging else { return }
        let mode = currentMode()
        if let m = mode, m != lastMode {
            let urls = Self.fileURLs(NSPasteboard(name: .drag))
            if !urls.isEmpty { wheel.show(for: urls, mode: m) }
        }
        lastMode = mode
    }

    private func stopDrag() {
        dragging = false
        lastMode = nil
        timer?.invalidate()
        timer = nil
    }

    static func fileURLs(_ pb: NSPasteboard) -> [URL] {
        let objs = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return (objs as? [URL]) ?? []
    }
}
