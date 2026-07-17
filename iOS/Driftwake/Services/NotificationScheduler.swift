import Foundation
import UserNotifications

/// Schedules the actual wake alarm as a local notification (works whether or not the app is
/// still alive in the background) and defines the "Snooze" action the quirky feature gates.
enum NotificationScheduler {
    static let wakeIdentifier = "driftwake.wake"
    static let alarmCategoryID = "DRIFTWAKE_ALARM"
    static let snoozeActionID = "SNOOZE"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func registerCategories() {
        let snooze = UNNotificationAction(identifier: snoozeActionID, title: "Snooze", options: [])
        let category = UNNotificationCategory(
            identifier: alarmCategoryID,
            actions: [snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func scheduleWakeAlarm(at date: Date, mode: AnchorDurationMode) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [wakeIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Driftwake"
        content.body = "Rise and shine — your \(mode.label) anchor is up."
        content.sound = .default
        content.categoryIdentifier = alarmCategoryID

        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: wakeIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancelWakeAlarm() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [wakeIdentifier])
    }
}
