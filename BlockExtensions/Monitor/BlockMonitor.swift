import Foundation
import DeviceActivity

/// Screen Time wakes this when a blocker's window opens or closes, when a
/// "Not now" pass runs out, and when a daily limit is used up. Every wake does
/// the same one thing: brings the shields in line with the rules.
///
/// The rules are asked a second ahead: Screen Time can call a window's start
/// a hair before the moment itself, and a hold judged at 5:59:59.9 for a
/// window opening at 6:00 would be judged closed.
final class BlockMonitor: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        BlockShields.reconcile(now: Date().addingTimeInterval(1))
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        BlockShields.reconcile(now: Self.judgeAt(endOf: activity))
    }

    /// When a "Not now" pass's interval ends, the rules are asked a second
    /// past the pass's own end, never earlier: Screen Time can end the
    /// interval a moment before the stored end, and a pass judged still
    /// running would leave the apps open with nothing left to wake us.
    static func judgeAt(endOf activity: DeviceActivityName, now: Date = Date()) -> Date {
        let raw = activity.rawValue
        guard raw.hasPrefix(BlockSchedule.passPrefix),
              let id = UUID(uuidString: String(raw.dropFirst(BlockSchedule.passPrefix.count))),
              let pass = BlockStore.load().passes.last(where: { $0.blockerID == id && $0.start <= now })
        else { return now.addingTimeInterval(1) }
        // Only a pass ending about now: judging at a later pass's end would
        // lift shields that should hold until then.
        guard pass.end.timeIntervalSince(now) < 60 else { return now.addingTimeInterval(1) }
        return max(now, pass.end).addingTimeInterval(1)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let raw = event.rawValue
        if raw.hasPrefix(BlockSchedule.limitPrefix),
           let id = UUID(uuidString: String(raw.dropFirst(BlockSchedule.limitPrefix.count))) {
            BlockStore.appendLimitHit(id)
        }
        BlockShields.reconcile()
    }
}
