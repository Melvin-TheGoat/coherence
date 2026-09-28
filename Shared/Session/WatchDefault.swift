import Foundation

/// When a session is measured by the Apple Watch (Aziz, 2026-09-28).
///
/// The switch on the Ready screen and in Settings is ON by default only when
/// this Watch has connected to 808 before and is connected now. The first
/// time the Watch really answers 808 (a start ack, or a measured session
/// landing; merely having 808 installed does not count), the switch turns
/// itself on; after that the person's own choice is kept. A Watch that is
/// not connected today never measures, whatever the switch says, and a phone
/// with no Watch paired never sees the switch at all.
enum WatchDefault {
    /// What the measuring choice becomes when the Watch answers 808:
    /// on, the first time; unchanged (nil) every time after.
    static func choiceOnConnect(everConnected: Bool) -> Bool? {
        everConnected ? nil : true
    }

    /// Whether Begin should ask the Watch to measure.
    static func measures(chosen: Bool, connected: Bool) -> Bool {
        chosen && connected
    }
}
