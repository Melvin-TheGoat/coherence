import Foundation
import os

/// A breadcrumb at every step of "Ask Otto": the notification, 808 coming
/// back, Otto's screen up and down, and every Screen Time call with how long
/// it took (2026-10-06, after Melvin's phone froze for about fifteen seconds
/// on his second "Ask Otto" in a row).
///
/// That freeze could not be made on a simulator, which has no shield, no
/// Screen Time daemon and no camera, so these lines are how a phone names
/// it. Stream them with the app's console (`OS_ACTIVITY_DT_MODE` mirrors
/// them to it):
///
///     DEVICECTL_CHILD_OS_ACTIVITY_DT_MODE=enable xcrun devicectl device \
///       process launch --console --terminate-existing --device <id> \
///       com.lockout.meditate808.dev
///
/// Nothing here is personal: step names, screen kinds and durations, never
/// an app, a token or a time of day. They stay on the phone like the rest of
/// Block (Screen Time's terms).
enum BlockTrace {
    static let log = Logger(subsystem: "com.lockout.meditate808", category: "Block")

    private static let lock = NSLock()
    private static var lastMain = "launch"
    private static var lastOther = "none"

    /// Logs a step, with seconds since boot so two lines can be subtracted
    /// by eye, and remembers it for `MainThreadWatch`.
    static func step(_ what: String) {
        let main = Thread.isMainThread
        lock.lock()
        if main { lastMain = what } else { lastOther = what }
        lock.unlock()
        let t = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        log.info("[\(t, privacy: .public)] \(main ? "main" : "bg", privacy: .public): \(what, privacy: .public)")
    }

    /// Runs `work`, logging how long it took; anything over a quarter of a
    /// second is logged as a warning, since on the main thread it is a hitch
    /// a person can feel.
    @discardableResult
    static func timed<T>(_ what: String, _ work: () throws -> T) rethrows -> T {
        step("\(what)…")
        let began = ProcessInfo.processInfo.systemUptime
        let result = try work()
        let took = ProcessInfo.processInfo.systemUptime - began
        if took > 0.25 {
            log.warning("\(what, privacy: .public) took \(took, format: .fixed(precision: 2), privacy: .public)s on \(Thread.isMainThread ? "MAIN" : "bg", privacy: .public)")
        }
        step("\(what) done in \(String(format: "%.3f", took))s")
        return result
    }

    /// What the main thread, and anything else, last said it was doing.
    static var lastSteps: (main: String, other: String) {
        lock.lock()
        defer { lock.unlock() }
        return (lastMain, lastOther)
    }
}

#if DEBUG
/// Development builds only (808 Beta is one): notices when the main thread
/// stops answering and names the last Block step it took, so a freeze on a
/// phone says where it was rather than only that it happened. A ping every
/// quarter second; one report once a second has gone by unanswered, and one
/// when it answers, with the full length.
final class MainThreadWatch: @unchecked Sendable {
    static let shared = MainThreadWatch()

    private let queue = DispatchQueue(label: "com.lockout.meditate808.main-watch", qos: .utility)
    private var timer: DispatchSourceTimer?
    /// When the ping now waiting on the main thread was sent. `queue` only.
    private var waitingSince: TimeInterval?
    private var reported = false

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 2, repeating: .milliseconds(250))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let since = waitingSince {
            let waited = now - since
            if waited >= 1, !reported {
                reported = true
                let steps = BlockTrace.lastSteps
                BlockTrace.log.error("MAIN THREAD NOT ANSWERING for \(waited, format: .fixed(precision: 1), privacy: .public)s. Main's last step: \(steps.main, privacy: .public). Elsewhere: \(steps.other, privacy: .public)")
            }
            return
        }
        waitingSince = now
        DispatchQueue.main.async { [self] in
            let answered = ProcessInfo.processInfo.systemUptime
            queue.async { [self] in
                if let since = waitingSince, answered - since >= 0.5 {
                    let steps = BlockTrace.lastSteps
                    BlockTrace.log.error("Main thread was blocked for \(answered - since, format: .fixed(precision: 2), privacy: .public)s. Main's last step: \(steps.main, privacy: .public). Elsewhere: \(steps.other, privacy: .public)")
                }
                waitingSince = nil
                reported = false
            }
        }
    }
}
#endif
