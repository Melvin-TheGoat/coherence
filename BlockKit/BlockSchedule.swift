import Foundation
import CryptoKit
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
/// plus its pass (Screen Time caps how many an app may monitor).
enum BlockSchedule {
    static let windowPrefix = "808.window."
    static let passPrefix = "808.pass."
    static let limitPrefix = "808.limit."

    static func windowName(_ id: UUID) -> DeviceActivityName { .init(windowPrefix + id.uuidString) }
    static func passName(_ id: UUID) -> DeviceActivityName { .init(passPrefix + id.uuidString) }
    static func limitEventName(_ id: UUID) -> DeviceActivityEvent.Name { .init(limitPrefix + id.uuidString) }

    /// Registers what changed and stops what is gone. Returns the names of
    /// blockers Screen Time refused, for the Block tab to say so.
    ///
    /// **Only what changed is restarted** (the review of 2026-09-22):
    /// restarting a window restarts its daily limit's count, so editing one
    /// blocker used to hand every daily limit a fresh allowance.
    @discardableResult
    static func sync(_ state: BlockState) -> [String] {
        let center = DeviceActivityCenter()
        var signatures = BlockStore.scheduleSignatures()
        let wanted = state.blockers.filter { $0.isOn && $0.hasApps && $0.windowProblem == nil }
        let wantedIDs = Set(wanted.map(\.id.uuidString))
        let existing = Set(state.blockers.map(\.id.uuidString))

        // Windows of blockers that are gone or off, and passes of blockers
        // that are gone.
        let stale = center.activities.filter { activity in
            let raw = activity.rawValue
            if raw.hasPrefix(windowPrefix) { return !wantedIDs.contains(String(raw.dropFirst(windowPrefix.count))) }
            if raw.hasPrefix(passPrefix) { return !existing.contains(String(raw.dropFirst(passPrefix.count))) }
            return false
        }
        if !stale.isEmpty { center.stopMonitoring(stale) }
        for key in signatures.keys where !wantedIDs.contains(key) { signatures[key] = nil }

        let running = Set(center.activities.map(\.rawValue))
        var refused: [String] = []
        for blocker in wanted {
            let key = blocker.id.uuidString
            let signature = self.signature(blocker)
            let name = windowName(blocker.id)
            if signatures[key] == signature && running.contains(name.rawValue) { continue }
            let (start, end) = components(blocker.window)
            let schedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true)
            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            if let minutes = blocker.dailyLimitMinutes {
                events[limitEventName(blocker.id)] = limitEvent(for: blocker.id, minutes: minutes)
            }
            center.stopMonitoring([name])
            do {
                try center.startMonitoring(name, during: schedule, events: events)
                signatures[key] = signature
            } catch {
                NSLog("Block: could not schedule %@: %@", blocker.name, String(describing: error))
                signatures[key] = nil
                refused.append(blocker.name)
            }
        }
        BlockStore.setScheduleSignatures(signatures)
        return refused
    }

    /// What Screen Time was told about a blocker: its hours, its limit, and
    /// its apps (by a hash of the selection, which is opaque tokens). Days,
    /// strictness and passes are the rules' business, not Screen Time's.
    static func signature(_ blocker: Blocker) -> String {
        let picked = (try? JSONEncoder().encode(BlockStore.selection(for: blocker.id))) ?? Data()
        let digest = SHA256.hash(data: picked).map { String(format: "%02x", $0) }.joined()
        return "\(blocker.window)|\(blocker.dailyLimitMinutes ?? -1)|\(digest)"
    }

    /// The daily limit's threshold over the picked apps. From iOS 17.4 it
    /// counts time already spent in the window, so a schedule registered
    /// mid-day does not grant the day's allowance a second time.
    private static func limitEvent(for id: UUID, minutes: Int) -> DeviceActivityEvent {
        let picked = BlockStore.selection(for: id)
        let threshold = DateComponents(minute: minutes)
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(applications: picked.applicationTokens,
                                       categories: picked.categoryTokens,
                                       webDomains: picked.webDomainTokens,
                                       threshold: threshold,
                                       includesPastActivity: true)
        }
        return DeviceActivityEvent(applications: picked.applicationTokens,
                                   categories: picked.categoryTokens,
                                   webDomains: picked.webDomainTokens,
                                   threshold: threshold)
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
    /// Returns when it will actually end, or nil if Screen Time refused both
    /// ways of asking, in which case the pass must not be taken.
    ///
    /// **Screen Time refuses an interval shorter than fifteen minutes**, so a
    /// five minute pass first asks with its interval starting in the past,
    /// sixteen minutes before its end. If that is refused it runs sixteen
    /// minutes from now instead: longer than asked, never open all day.
    /// Which of the two a phone accepts is the first thing to check on one.
    static func schedulePassEnd(for id: UUID, at end: Date, now: Date = Date()) -> Date? {
        let center = DeviceActivityCenter()
        let name = passName(id)
        center.stopMonitoring([name])
        let margin: TimeInterval = 16 * 60
        let exact = DateInterval(start: min(now, end.addingTimeInterval(-margin)), end: end)
        if start(name, exact, in: center) { return end }
        let longer = max(end, now.addingTimeInterval(margin))
        if start(name, DateInterval(start: now, end: longer), in: center) { return longer }
        return nil
    }

    private static func start(_ name: DeviceActivityName, _ interval: DateInterval,
                              in center: DeviceActivityCenter) -> Bool {
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: interval.start),
            intervalEnd: calendar.dateComponents(fields, from: interval.end),
            repeats: false)
        do {
            try center.startMonitoring(name, during: schedule)
            return true
        } catch {
            NSLog("Block: a pass end was refused: %@", String(describing: error))
            return false
        }
    }

    /// Everything off: Screen Time access was withdrawn.
    static func stopAll() {
        let center = DeviceActivityCenter()
        let ours = center.activities.filter { $0.rawValue.hasPrefix("808.") }
        if !ours.isEmpty { center.stopMonitoring(ours) }
        BlockStore.setScheduleSignatures([:])
    }
}
