import SwiftUI
import UserNotifications

@main
struct DriftwakeApp: App {
    @StateObject private var store: Store
    @StateObject private var appModel: AppModel
    private let notificationDelegate = NotificationDelegate()

    init() {
        let s = Store()
        let m = AppModel()
        m.store = s
        notificationDelegate.appModel = m
        UNUserNotificationCenter.current().delegate = notificationDelegate
        _store = StateObject(wrappedValue: s)
        _appModel = StateObject(wrappedValue: m)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(appModel)
        }
    }
}
