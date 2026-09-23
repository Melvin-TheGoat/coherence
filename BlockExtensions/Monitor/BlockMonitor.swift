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
        BlockShields.reconcile(now: Date().addingTimeInterval(1))
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
