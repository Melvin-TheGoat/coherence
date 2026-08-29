import Foundation

/// WatchConnectivity dictionary keys shared by both sides. The Codable
/// `SessionParams` / `SessionPayload` are JSON-encoded to `Data` under these keys.
enum WCKeys {
    /// Phone → Watch: JSON-encoded `SessionParams`.
    static let params = "params"
    /// Phone → Watch (application context): whether onboarding is complete on
    /// the phone. The Watch's start screen gates Begin on it, because a wrist
    /// session before the phone is set up delivers into an app that cannot
    /// receive it. Rides EVERY context update, including the post-session
    /// clear, so the flag survives the start command's lifecycle.
    static let onboarded = "onboarded"
    /// Watch → Phone: JSON-encoded `SessionPayload`.
    static let payload = "payload"
    /// Phone → Watch: end the running session now (the phone's mid-session End
    /// button). Value is the session's UUID string, so a stale end can't stop a
    /// later session. The Watch still owns the authoritative finish + haptic.
    static let end = "end"
    /// Watch → Phone: the session could not start. Value is a `StartFailure`
    /// raw value, so the phone can show the right recovery screen instead of
    /// leaving the user on a mid-session screen for a session that never began.
    static let startFailure = "startFailure"
    /// Watch → Phone: the workout actually began. Value is
    /// "<sessionID>|<epochSeconds>" — the phone re-anchors its mid-session
    /// clock and audio timer to the Watch's real start, instead of guessing
    /// from `startWatchApp` (which fires seconds earlier and made timed
    /// sessions hit 0:00 on the phone while the Watch still had time left).
    static let started = "started"
    /// Watch → Phone: a session the WATCH initiated has begun. Value is
    /// "<sessionID>|<epochSeconds>|<soundID or empty>" — the phone joins it:
    /// shows its mid-session screen and plays the chosen sound. Sent over
    /// sendMessage ONLY, never the queued channels: a queued join replaying
    /// hours later would resurrect a dead session's live screen, and if the
    /// phone isn't reachable right now there is nothing for it to do anyway
    /// (the session runs in silence and the payload still arrives).
    static let watchBegin = "watchBegin"
    /// Watch → Phone: the user tapped End; the engine is now scoring and the
    /// payload follows in a few seconds. Value is the session's UUID string.
    /// Lets the phone drop its live screen IMMEDIATELY and show a small
    /// "receiving" note instead of appearing frozen while the Watch finishes
    /// the workout, waits out the HRV settle, and ships. sendMessage only —
    /// a queued replay of an old "ending" must not touch a live session, and
    /// an unreachable phone has no live screen to drop anyway.
    static let ending = "ending"
}

/// Why a session refused to start on the Watch. Sent to the phone so it can
/// take down the mid-session screen and explain what to fix.
enum StartFailure: String, Codable, Identifiable {
    var id: String { rawValue }

    /// Heart rate isn't readable — permission denied, or the Watch isn't worn.
    /// HR is the signal we can't do without, so we stop rather than record a
    /// session with a hole in it.
    case heartRateUnavailable
    /// The `.mindAndBody` workout couldn't be recorded (workout SHARE denied).
    case workoutNotAuthorized
    /// `startWatchApp` itself failed — watch app not installed, watch not
    /// paired/reachable. Raised by the PHONE (not the Watch); previously this
    /// failed silently and the session just never happened.
    case watchUnreachable
    /// No Apple Watch is paired with this iPhone. Checked before launching, so
    /// the user is told the actual reason instead of watching a launch fail.
    case watchNotPaired
    /// A Watch is paired but 808 is not installed on it. This is the one the
    /// phone used to report as "didn't answer", which sent people to re-check
    /// permissions for a problem that was never about permissions.
    case watchAppNotInstalled
}
