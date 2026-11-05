import AppKit

/// Окно, которое появляется поверх всех окон и НЕ делает приложение активным.
/// Finder остаётся на переднем плане: ничего не переключается и никакие другие окна не открываются.
final class DialogPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

struct DialogField {
    var label: String = ""
    var value: String = ""
    var secure: Bool = false
}

struct DialogResult {
    let button: Int
    let values: [String]
}

@MainActor
final class DialogController: NSObject {
    let panel: DialogPanel
    var completion: ((DialogResult?) -> Void)?
    private var textFields: [NSTextField] = []
    private var cancelIndex = 0
    private var finished = false

    init(title: String, message: String, fields: [DialogField], buttons: [String], vertical: Bool) {
        panel = DialogPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        super.init()
        build(title: title, message: message, fields: fields, buttons: buttons, vertical: vertical)
    }

    private func build(title: String, message: String, fields: [DialogField], buttons: [String], vertical: Bool) {
        let width: CGFloat = 360
        let inner = width - 40

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 160))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        if !message.isEmpty {
            let msg = NSTextField(wrappingLabelWithString: message)
            msg.font = NSFont.systemFont(ofSize: 12)
            msg.textColor = NSColor.secondaryLabelColor
            msg.widthAnchor.constraint(equalToConstant: inner).isActive = true
            stack.addArrangedSubview(msg)
        }

        for f in fields {
            let field: NSTextField = f.secure ? NSSecureTextField(frame: .zero) : NSTextField(frame: .zero)
            field.stringValue = f.value
            textFields.append(field)
            if f.label.isEmpty {
                field.widthAnchor.constraint(equalToConstant: inner).isActive = true
                stack.addArrangedSubview(field)
            } else {
                let label = NSTextField(labelWithString: f.label)
                label.widthAnchor.constraint(equalToConstant: 64).isActive = true
                field.widthAnchor.constraint(equalToConstant: inner - 72).isActive = true
                let row = NSStackView(views: [label, field])
                row.orientation = .horizontal
                row.spacing = 8
                stack.addArrangedSubview(row)
            }
        }

        let all = buttons + ["Отмена"]
        cancelIndex = all.count - 1
        var buttonViews: [NSButton] = []
        for (i, t) in all.enumerated() {
            let b = NSButton(title: t, target: self, action: #selector(pressed(_:)))
            b.tag = i
            b.bezelStyle = .rounded
            if i == cancelIndex {
                b.keyEquivalent = "\u{1b}"
            } else if i == 0 && !vertical {
                b.keyEquivalent = "\r"
            }
            buttonViews.append(b)
        }

        if vertical {
            for b in buttonViews {
                b.widthAnchor.constraint(equalToConstant: inner).isActive = true
                stack.addArrangedSubview(b)
            }
        } else {
            let spacer = NSView()
            spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            var views: [NSView] = [spacer]
            for b in buttonViews.reversed() { views.append(b) }
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.spacing = 8
            row.widthAnchor.constraint(equalToConstant: inner).isActive = true
            stack.addArrangedSubview(row)
        }

        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -16)
        ])

        panel.contentView = effect
        effect.layoutSubtreeIfNeeded()
        let height = max(stack.fittingSize.height + 34, 110)
        panel.setContentSize(NSSize(width: width, height: height))

        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.onCancel = { [weak self] in self?.finish(nil) }
    }

    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        if let f = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                         y: f.minY + f.height * 0.62 - size.height / 2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        if let first = textFields.first {
            panel.makeFirstResponder(first)
            first.selectText(nil)
        }
    }

    @objc private func pressed(_ sender: NSButton) {
        finish(sender.tag == cancelIndex ? nil : sender.tag)
    }

    private func finish(_ index: Int?) {
        guard !finished else { return }
        finished = true
        let values = textFields.map { $0.stringValue }
        panel.orderOut(nil)
        let done = completion
        completion = nil
        if let i = index {
            done?(DialogResult(button: i, values: values))
        } else {
            done?(nil)
        }
    }
}

@MainActor
enum Dialogs {
    private static var active: [DialogController] = []

    /// Показывает окно и ждёт ответа. Возвращает nil, если нажали «Отмена» или Esc.
    static func show(title: String, message: String = "", fields: [DialogField] = [],
                     buttons: [String], vertical: Bool = false) async -> DialogResult? {
        await withCheckedContinuation { (cont: CheckedContinuation<DialogResult?, Never>) in
            let c = DialogController(title: title, message: message, fields: fields,
                                     buttons: buttons, vertical: vertical)
            active.append(c)
            c.completion = { result in
                active.removeAll { $0 === c }
                cont.resume(returning: result)
            }
            c.present()
        }
    }

    /// Окно с одним полем. nil, если «Отмена» или поле пустое.
    static func askText(title: String, message: String, defaultValue: String = "", secure: Bool = false) async -> String? {
        let field = DialogField(label: "", value: defaultValue, secure: secure)
        guard let r = await show(title: title, message: message, fields: [field], buttons: ["OK"]),
              let text = r.values.first else { return nil }
        let value = text.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Поднимает окна самого приложения (главное, настройки) поверх остальных
    static func raiseAppWindows() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.isVisible && w.canBecomeKey {
            w.orderFrontRegardless()
        }
    }
}
