import Foundation
import UserNotifications

/// A notification to show now (date == nil) or at a set moment.
struct PlannedNotification: Equatable {
    let id: String
    let title: String
    let body: String
    let date: Date?
    /// Notification category, for action buttons (see `UserNotificationService.stopCategory`).
    var category: String? = nil
}

protocol NotificationPosting: AnyObject {
    func requestAuthorization() async -> Bool
    func isDenied() async -> Bool
    /// Replaces all scheduled peak notifications with this plan.
    func replaceScheduled(_ plan: [PlannedNotification], ids: [String])
    func post(_ notification: PlannedNotification)
    /// Called with the notification id when the user clicks a notification.
    var onOpen: ((String) -> Void)? { get set }
    /// Called when the user clicks "Stop" in a notification.
    var onStop: (() -> Void)? { get set }
}

final class UserNotificationService: NSObject, NotificationPosting, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var onOpen: ((String) -> Void)?

    static let stopCategory = "sound"
    static let stopAction = "stop"
    var onStop: (() -> Void)?

    /// `stopTitle` is the localized label of the Stop button on adhan and pre-adhan notifications.
    init(stopTitle: String = "Stop") {
        super.init()
        center.delegate = self
        let stop = UNNotificationAction(identifier: Self.stopAction, title: stopTitle, options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.stopCategory, actions: [stop], intentIdentifiers: [], options: []),
        ])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    func replaceScheduled(_ plan: [PlannedNotification], ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
        plan.forEach(post)
    }

    func post(_ n: PlannedNotification) {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = .default
        if let category = n.category { content.categoryIdentifier = category }
        var trigger: UNNotificationTrigger?
        if let date = n.date {
            let interval = date.timeIntervalSinceNow
            guard interval > 1 else { return }
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        }
        center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger))
    }

    // Show banners even though a menu bar app counts as "active".
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            if action == Self.stopAction { self.onStop?() } else { self.onOpen?(id) }
        }
        completionHandler()
    }
}
