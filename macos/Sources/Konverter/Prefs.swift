import Foundation
import AppKit

/// Все настройки приложения (хранятся в UserDefaults, окно настроек пишет в те же ключи)
enum Prefs {
    private static let d = UserDefaults.standard

    static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
    static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    static func string(_ k: String, _ def: String) -> String { d.string(forKey: k) ?? def }

    // куда сохранять
    static var saveMode: Int { int("saveMode", 0) }            // 0 рядом, 1 подпапка Converted, 2 выбранная папка
    static var outputFolder: String? {
        let s = string("outputFolder", "")
        return s.isEmpty ? nil : s
    }
    static var trashOriginal: Bool { bool("trashOriginal", false) }

    // уведомления
    static var notify: Bool { bool("notify", true) }
    static var sound: Bool { bool("sound", true) }

    // качество
    static var imageQuality: Int { int("imageQuality", 90) }
    static var imageMaxSide: Int { int("imageMaxSide", 0) }
    static var audioBitrate: Int { int("audioBitrate", 192) }
    static var videoQuality: Int { int("videoQuality", 1) }    // 0 высокое, 1 среднее, 2 малое
    static var videoMaxHeight: Int { int("videoMaxHeight", 0) }

    // какая кнопка открывает какое колесо
    static func modifier(for mode: WheelMode) -> NSEvent.ModifierFlags? {
        let value: String
        switch mode {
        case .convert: value = string("modConvert", "shift")
        case .tools: value = string("modTools", "command")
        case .actions: value = string("modActions", "control")
        }
        switch value {
        case "shift": return .shift
        case "command": return .command
        case "control": return .control
        case "option": return .option
        default: return nil
        }
    }

    // свои колёса форматов
    static func wheelState(_ kind: Kind) -> (order: [String], hidden: Set<String>) {
        let all = kind.outputs
        var order = (d.stringArray(forKey: "wheelOrder.\(kind.key)") ?? []).filter { all.contains($0) }
        for f in all where !order.contains(f) { order.append(f) }
        let hidden: Set<String>
        if let h = d.stringArray(forKey: "wheelHidden.\(kind.key)") {
            hidden = Set(h)
        } else {
            hidden = Set(kind.defaultHidden)
        }
        return (order, hidden)
    }

    static func saveWheel(_ kind: Kind, order: [String], hidden: Set<String>) {
        d.set(order, forKey: "wheelOrder.\(kind.key)")
        d.set(Array(hidden), forKey: "wheelHidden.\(kind.key)")
    }

    static func resetWheel(_ kind: Kind) {
        d.removeObject(forKey: "wheelOrder.\(kind.key)")
        d.removeObject(forKey: "wheelHidden.\(kind.key)")
    }
}
