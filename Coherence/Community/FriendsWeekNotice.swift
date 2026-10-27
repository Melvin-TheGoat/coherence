import Foundation
import UserNotifications

/// "You and Aziz finished the week 🎉": the notification on the phone of
/// whoever finished a shared week (2026-10-27). The friend hears it as a
/// CloudKit push instead (`GOAL_WEEK_ALERT`), sent by this same phone.
/// Shown at once, once per week (its identifier is the week's), and a tap
/// opens Friends like any goal push.
enum FriendsWeekNotice {
    static let userInfoKey = "friendsWeek"

    static func post(_ week: TogetherWeek, center: UNUserNotificationCenter = .current()) {
        let content = UNMutableNotificationContent()
        content.title = "You and \(week.partnerName) finished the week 🎉"
        let days = week.target == 1 ? "1 day" : "\(week.target) days"
        content.body = "You both meditated \(days) this week. +\(FriendsLedger.pointsPerWeek) points for Otto's hats."
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = [userInfoKey: week.goalID]
        center.add(UNNotificationRequest(identifier: "friends.week." + week.id, content: content, trigger: nil))
    }
}
