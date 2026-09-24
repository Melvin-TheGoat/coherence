import Foundation
import SwiftUI
import UserNotifications

/// Whether leaving 808 mid-sit costs the session, and how long is too long.
///
/// Melvin, 2026-09-23: "if they leave for more than 10 seconds then the
/// meditation doesn't count." Pure and apart from `SessionCoordinator` so
/// the two facts that decide everything else — how long is forgiven, and
/// what counts as leaving at all — can be proven right with no session
/// actually running.
enum LeftAppRule {

    /// Away longer than this and the sit is voided; at or under, it simply
    /// carries on.
    static let graceSec: TimeInterval = 10

    enum Verdict: Equatable { case continues, voided }

    static func verdict(awaySec: TimeInterval) -> Verdict {
        awaySec > graceSec ? .voided : .continues
    }

    /// Only `.background` is leaving. `.inactive` covers Control Center, the
    /// Notification Center swipe, and a system alert passing over the
    /// screen — someone turning the volume down mid-sit hasn't left it.
    static func isLeaving(_ phase: ScenePhase) -> Bool {
        phase == .background
    }

    /// Only a phone-measured sit can be left. A Watch sit is measured on the
    /// wrist regardless of what the phone's screen is doing, so it is exempt.
    static func applies(engine: SessionCoordinator.Engine) -> Bool {
        engine == .phone
    }
}

/// The notification that says "come back," posted the moment 808 goes to
/// the background mid-sit (Melvin, 2026-09-23: "should send a notification
/// saying hey come back or else your meditation won't count").
///
/// Posted with no delay — the trigger is `nil`, which UserNotifications
/// treats as "as soon as possible" — since the whole point is reaching
/// whatever screen the person went to before the ten-second grace period
/// runs out. **Time Sensitive**, the same reasoning as `SessionEndNotice`:
/// the Ready screen's own Silence switch may have turned on Do Not Disturb,
/// which would otherwise swallow the one notification that matters most.
/// **Never asks for permission** — Begin already did, for the end-of-session
/// notice — so someone who said no to that stays silently ungated by this
/// one too, rather than being asked twice in one sit.
enum LeftAppNotice {
    static let userInfoKey = "leftApp"
    private static func id(_ session: UUID) -> String { "left-app-\(session.uuidString)" }

    static func post(for session: UUID) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Come back to your session"
        content.body = "Open 808 within 10 seconds or this session won't count."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = [userInfoKey: session.uuidString]
        // `post` is itself async, which makes the `async throws` overload of
        // `add` the one Swift resolves to here (unlike `SessionEndNotice`'s
        // sync `schedule`, which gets the completion-handler one). Errors are
        // swallowed the same way that one drops them with a nil handler.
        try? await center.add(UNNotificationRequest(identifier: id(session), content: content, trigger: nil))
    }

    /// Coming back: the notification's job is done, whether it had already
    /// fired or was still waiting to. Delivered notifications are cleared
    /// too — unlike `SessionEndNotice`, this one has usually already shown
    /// by the time anyone can react to it.
    static func cancel(for session: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id(session)])
        center.removeDeliveredNotifications(withIdentifiers: [id(session)])
    }
}
