import Foundation
import UserNotifications

/// The notification that tells you a timed session is over (Aziz, 2026-09-22:
/// "we have to add notifications to this").
///
/// A timed sit is usually done with the phone face down or locked, and with a
/// silent session nothing keeps 808 awake, so without this the end of the
/// timer was silent: the session only finished once somebody picked the phone
/// up. It is scheduled when the sit starts, for the planned end, and taken
/// back the moment the sit ends another way.
///
/// **Time Sensitive**, because it is a timer the person set themselves, and
/// the Ready screen's own "Silence notifications" switch turns on Do Not
/// Disturb, which would otherwise swallow the one notification they asked
/// for. With 808 on screen it plays only its sound; the sit screen is already
/// saying the session is over (`BlockNotifications.willPresent`).
enum SessionEndNotice {
    static let userInfoKey = "sessionEnd"
    private static func id(_ session: UUID) -> String { "session-end-\(session.uuidString)" }

    /// Asks for permission if it has never been asked. Called from Begin on a
    /// timed session only, because that is the moment the question is about
    /// something; never on appear, where a system dialog would be the first
    /// thing in front of somebody about to close their eyes.
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func schedule(for session: UUID, afterSeconds seconds: Int) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = SessionLength.endTitle(minutes: max(1, seconds / 60))
        content.body = "Your session is done. Take a breath before you get up."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = [userInfoKey: session.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id(session), content: content, trigger: trigger))
    }

    /// The sit ended some other way (End, early): the notification must not
    /// arrive later claiming a session that is already over.
    static func cancel(for session: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(session)])
    }
}
