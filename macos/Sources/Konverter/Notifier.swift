import AppKit
import UserNotifications

/// Уведомление в Центре уведомлений и звук после конвертации
@MainActor
enum Notifier {
    static func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotifyDelegate.shared
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func finished(_ title: String, _ body: String, ok: Bool) {
        if Prefs.sound { NSSound(named: ok ? "Glass" : "Basso")?.play() }
        guard Prefs.notify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifyDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
