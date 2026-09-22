import Foundation
import DeviceActivity
import FamilyControls

/// Tells Screen Time when to wake the monitor extension: when each blocker's
/// window opens and closes, when a "Not now" pass runs out, and when a daily
/// limit is used up. The monitor then calls `BlockShields.reconcile`, so the
/// apps close and open on time even when 808 is not running.
///
/// One daily schedule per blocker, whatever its days: the weekday rule lives
/// in `BlockRules`, which the monitor asks on every wake, so a weekend simply
/// wakes it to find nothing to hold. That keeps each blocker to one activity
/// (Screen Time caps how many an app may monitor).
enum BlockSchedule {
    static let windowPrefix = "808.window."
    static let passPrefix = "808.pass."
    static let limitPrefix = "808.limit."

    static func windowName(_ id: UUID) -> DeviceActivityName { .init(windowPrefix + id.uuidString) }
    static func passName(_ id: UUID) -> DeviceActivityName { .init(passPrefix + id.uuidString) }
    static func limitEventName(_ id: UUID) -> DeviceActivityEvent.Name { .init(limitPrefix + id.uuidString) }

    /// Re-registers every blocker's window, replacing whatever was there.
    static func sync(_ state: BlockState) {
        let center = DeviceActivityCenter()
        let windows = center.activities.filter { $0.rawValue.hasPrefix(windowPrefix) }
        if !windows.isEmpty { center.stopMonitoring(windows) }

        for blocker in state.blockers where blocker.isOn && blocker.hasApps {
            let (start, end) = components(blocker.window)
            let schedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true)
            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            if let minutes = blocker.dailyLimitMinutes {
                let picked = BlockStore.selection(for: blocker.id)
                events[limitEventName(blocker.id)] = DeviceActivityEvent(
                    applications: picked.applicationTokens,
                    categories: picked.categoryTokens,
                    webDomains: picked.webDomainTokens,
                    threshold: DateComponents(minute: minutes))
            }
            do {
                try center.startMonitoring(windowName(blocker.id), during: schedule, events: events)
            } catch {
                NSLog("Block: could not schedule %@: %@", blocker.name, String(describing: error))
            }
        }
    }

    /// The hours of a window as Screen Time wants them. All day is midnight
    /// to one second before the next; an end at or before the start crosses
    /// midnight, which Screen Time reads the same way.
    static func components(_ window: BlockWindow) -> (DateComponents, DateComponents) {
        switch window {
        case .allDay:
            return (DateComponents(hour: 0, minute: 0, second: 0),
                    DateComponents(hour: 23, minute: 59, second: 59))
        case .hours(let start, let end):
            let open = DateComponents(hour: (start / 60) % 24, minute: start % 60)
            let close = end % 1440 == 0
                ? DateComponents(hour: 23, minute: 59, second: 59)
                : DateComponents(hour: (end / 60) % 24, minute: end % 60)
            return (open, close)
        }
    }

    /// Wakes the monitor when a pass ends, so the apps close again on time.
    ///
    /// **Screen Time refuses an interval shorter than fifteen minutes**, so a
    /// five minute pass starts its interval in the past and ends on time.
    /// Written down in CONSISTENCY.md as the thing to verify on a phone first.
    static func schedulePassEnd(for id: UUID, at end: Date, now: Date = Date()) {
        let start = min(now, end.addingTimeInterval(-15 * 60))
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: start),
            intervalEnd: calendar.dateComponents(fields, from: end),
            repeats: false)
        let center = DeviceActivityCenter()
        center.stopMonitoring([passName(id)])
        do {
            try center.startMonitoring(passName(id), during: schedule)
        } catch {
            NSLog("Block: could not schedule a pass end: %@", String(describing: error))
        }
    }

    /// Everything off: used when Screen Time access is withdrawn.
    static func stopAll() {
        let center = DeviceActivityCenter()
        let ours = center.activities.filter { $0.rawValue.hasPrefix("808.") }
        if !ours.isEmpty { center.stopMonitoring(ours) }
    }
}
