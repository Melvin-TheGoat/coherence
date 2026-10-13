import Foundation
import UserNotifications

/// The reminder switch's front door: asks iOS for permission, then hands the
/// scheduling to `ReminderScheduler`, which plans every reminder from what
/// is stored (2026-10-12). Before that this file scheduled ONE repeating
/// notification at the chosen time, every day, whether or not the person had
/// already meditated.
enum NotificationScheduler {
    /// The old repeating reminder's identifier, still recognised on a tap
    /// (`Analytics.notificationKind`) until every phone has replanned.
    static let reminderID = ReminderScheduler.legacyID

    /// Requests permission then replans (or cancels) based on `enabled`. The
    /// time is read from Preferences by the planner; callers set it first.
    /// `onDenied` fires on the main thread when the OS refuses, so the caller
    /// can flip its switch back OFF: a toggle showing ON while the system will
    /// never deliver anything is the settings screen lying.
    @MainActor
    static func apply(enabled: Bool, at time: Date?,
                      onDenied: (() -> Void)? = nil) {
        guard enabled, time != nil else {
            ReminderScheduler.cancelAll()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else { onDenied?(); return }
                ReminderScheduler.replan()
            }
        }
    }
}
