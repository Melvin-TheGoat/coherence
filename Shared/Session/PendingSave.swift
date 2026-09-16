import Foundation

/// The session that has finished but has not been through Save session yet.
///
/// Aziz, 2026-09-15: "once you open the phone after your meditation session is
/// over it should take you straight to the grading the meditation."
///
/// The hand-off that existed was in memory only: `SessionCoordinator.persist`
/// sets `lastSessionID`, `FriendsHooks` watches it, and the sheet opens. That
/// works only while the app is alive and on screen. A session almost never
/// ends that way. You sit with the phone face down or locked, the Watch ships
/// the payload, and by the time you pick the phone up the app has been
/// suspended for ten minutes or killed outright. `lastSessionID` is then
/// either already spent or gone with the process, so the person came back to
/// the Home screen with the session quietly stored as private and no prompt
/// to grade it.
///
/// So the id is written to UserDefaults the instant a session persists, and
/// read back on launch and on every return to the foreground. UserDefaults
/// rather than the session row itself because this is a piece of UI state
/// ("we still owe this person a screen"), not a fact about the meditation.
public enum PendingSave {
    static let key = "session.pendingSave.v1"
    static let stampKey = "session.pendingSave.at.v1"

    /// Past this, a waiting session is no longer "the one you just did".
    /// Opening a save sheet for a sit you forgot about two days ago would be
    /// a jump scare, and the session is safely stored either way: it can
    /// still be shared later from its own results screen.
    static let maxAge: TimeInterval = 12 * 60 * 60

    public static func set(_ id: UUID, at date: Date = Date(), in defaults: UserDefaults = .standard) {
        defaults.set(id.uuidString, forKey: key)
        defaults.set(date.timeIntervalSince1970, forKey: stampKey)
    }

    public static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: stampKey)
    }

    /// The session still waiting to be graded, or nil. Reading one that has
    /// gone stale clears it, so this never has to be swept separately.
    public static func read(now: Date = Date(), in defaults: UserDefaults = .standard) -> UUID? {
        guard let raw = defaults.string(forKey: key), let id = UUID(uuidString: raw) else { return nil }
        let stamp = defaults.double(forKey: stampKey)
        guard stamp > 0, now.timeIntervalSince1970 - stamp <= maxAge else {
            clear(in: defaults)
            return nil
        }
        return id
    }
}
