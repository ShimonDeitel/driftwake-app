import Foundation
import UserNotifications

/// Bridges the system notification center back into `AppModel`: when the wake alarm fires
/// (foregrounded or via the "Snooze" action), the model needs to know so the UI can show the
/// alarm screen and the snooze quirk can run its check.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    weak var appModel: AppModel?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier == NotificationScheduler.wakeIdentifier {
            Task { @MainActor [weak self] in
                self?.appModel?.handleAlarmFired()
            }
        }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier == NotificationScheduler.wakeIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor [weak self] in
            if response.actionIdentifier == NotificationScheduler.snoozeActionID {
                self?.appModel?.handleSnoozeTapped()
            } else {
                self?.appModel?.handleAlarmFired()
            }
            completionHandler()
        }
    }
}
