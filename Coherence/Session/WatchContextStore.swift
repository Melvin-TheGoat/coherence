import Foundation
import WatchConnectivity

/// Everything the phone keeps in the Watch's application context, in one
/// place (2026-10-12).
///
/// `updateApplicationContext` REPLACES the whole dictionary, so every update
/// must carry every key. The context used to hold only a session's start
/// command and the onboarded flag, and each caller wrote both by hand. With
/// Otto's glow and the + screen's length riding it too, a widget refresh in
/// the moment a session was starting would have cleared that session's start
/// command. So every caller sets its own part here and calls `push()`.
@MainActor
enum WatchContextStore {
    /// The start command of the session being handed to the Watch, until its
    /// payload lands or the phone releases it. Nil the rest of the time.
    static var params: Data?
    /// Whether this phone has finished onboarding (the Watch gates Begin on it).
    static var onboarded = false
    /// Otto's glow for the next few days: the widget's own snapshot.
    static var glowSnapshot: Data?
    /// The + screen's remembered length, in seconds; 0 for open.
    static var defaultLengthSec = 0

    private static var lastSent: [String: Any] = [:]

    static func push() {
        guard WCSession.isSupported() else { return }
        let wc = WCSession.default
        guard wc.activationState == .activated else { return }
        var context: [String: Any] = [
            WCKeys.onboarded: onboarded,
            WCKeys.defaultLength: defaultLengthSec,
        ]
        if let params { context[WCKeys.params] = params }
        if let glowSnapshot { context[WCKeys.glowSnapshot] = glowSnapshot }
        // The same context again costs the Watch a wake for nothing.
        guard !NSDictionary(dictionary: context).isEqual(to: lastSent) else { return }
        do {
            try wc.updateApplicationContext(context)
            lastSent = context
        } catch {
            // Not paired, or the Watch app is not installed: nothing to tell.
        }
    }

    /// From the widget publisher, whenever Otto's glow or the length may
    /// have moved. Pushes only when either did.
    static func update(glow snapshot: OttoWidgetSnapshot, defaultLengthSec: Int?) {
        let encoder = JSONEncoder()
        var forWatch = snapshot
        // `written` changes on every call; it is not news to the Watch.
        forWatch.written = .distantPast
        let data = try? encoder.encode(forWatch)
        let length = defaultLengthSec ?? 0
        guard data != glowSnapshot || length != self.defaultLengthSec else { return }
        glowSnapshot = data
        self.defaultLengthSec = length
        push()
    }
}
