import Foundation
import UserNotifications

/// Tells the user that a new version has been downloaded, with a notification from macOS. Nobody keeps
/// the menu of a menu bar app open, so a button inside it would wait there unseen for days.
final class UpdateNotice: NSObject, UNUserNotificationCenterDelegate {
    private static let identifier = "update"
    private static let restartAction = "restart"

    /// Installs the update and restarts.
    private let restart: () -> Void
    /// Opens seshka's menu, where the same update waits with its button.
    private let open: () -> Void
    private var announced: String?

    /// macOS only delivers notifications for an app bundle, not for the bare program the tests run.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    init(restart: @escaping () -> Void, open: @escaping () -> Void) {
        self.restart = restart
        self.open = open
        super.init()
        center?.delegate = self
        let action = UNNotificationAction(identifier: Self.restartAction, title: "Restart now", options: [])
        center?.setNotificationCategories([
            UNNotificationCategory(identifier: Self.identifier, actions: [action], intentIdentifiers: [])
        ])
    }

    /// Once per version. macOS asks for permission the first time, which is the first update that arrives.
    func announce(_ version: String) {
        guard announced != version, let center else { return }
        announced = version
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "seshka \(version) is ready"
            content.body = "Restart seshka to start using it."
            content.categoryIdentifier = Self.identifier
            center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil))
        }
    }

    func withdraw() {
        announced = nil
        center?.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// seshka is always running, and a running app's notifications are hidden unless it says otherwise.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            if action == Self.restartAction {
                self.restart()
            } else if action == UNNotificationDefaultActionIdentifier {
                self.open()
            }
        }
        completionHandler()
    }
}
