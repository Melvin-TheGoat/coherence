import Foundation
import UserNotifications

/// Schedules the single daily meditation reminder. One repeating local
/// notification at the chosen time; rescheduled on change, cancelled when off.
enum NotificationScheduler {
    private static let reminderID = "daily-meditation-reminder"

    /// Requests permission then schedules (or cancels) based on `enabled`.
    static func apply(enabled: Bool, at time: Date?) {
        let center = UNUserNotificationCenter.current()
        guard enabled, let time else {
            center.removePendingNotificationRequests(withIdentifiers: [reminderID])
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            schedule(at: time)
        }
    }

    private static func schedule(at time: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])

        let content = UNMutableNotificationContent()
        content.title = "Time to meditate"
        content.body = "A few minutes of stillness. Your practice is waiting."
        content.sound = .default

        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger))
    }
}
