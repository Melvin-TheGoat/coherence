import Foundation

// Block: Otto holds the apps a person picked until they have meditated in the
// window they chose (Melvin, 2026-09-21/22; `CONSISTENCY.md` is the design and
// `mockups/block-v1.html` the approved look).
//
// This file is the RULES, pure Foundation, so they are tested without a phone
// and shared by the app and the three Screen Time extensions (which list this
// file among their sources). Nothing here knows which apps were picked: those
// are opaque Screen Time tokens that live in BlockKit, and per Apple's Family
// Controls terms none of it ever leaves the phone.

/// When a blocker holds apps in a day.
enum BlockWindow: Codable, Equatable, Hashable {
    /// Midnight to midnight: Mindful day.
    case allDay
    /// Minutes from midnight. An `end` at or before `start` runs past
    /// midnight into the next day; 1440 is midnight itself.
    case hours(start: Int, end: Int)
}

/// How hard Otto holds (CONSISTENCY.md, "What you can set").
enum BlockStrictness: String, Codable, CaseIterable {
    /// He asks once, then "Not now" works.
    case chill
    /// A ten second breath with Otto before "Not now" works.
    case firm
    /// No "Not now" at all. Meditating is the only way in.
    case strict

    var label: String {
        switch self {
        case .chill: return "Chill"
        case .firm: return "Firm"
        case .strict: return "Strict"
        }
    }

    var explanation: String {
        switch self {
        case .chill: return "Otto asks once, then you can have a few minutes."
        case .firm: return "Breathe with Otto for ten seconds before you can have a few minutes."
        case .strict: return "No passes. A session is the only way in."
        }
    }
}

enum BlockerKind: String, Codable, CaseIterable {
    case mindfulDay, mindfulMorning, windDown, focusHours, dailyLimit, custom
}

/// One blocker. Its apps are kept separately, as Screen Time tokens.
struct Blocker: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: BlockerKind
    var name: String
    var isOn = false
    /// Calendar weekdays it runs on: 1 is Sunday, 7 is Saturday.
    var weekdays: Set<Int> = Set(1...7)
    var window: BlockWindow = .allDay
    var strictness: BlockStrictness = .chill
    /// "Not now" passes a day. nil is no limit. Strict takes none.
    var passesPerDay: Int? = 3
    /// The shortest session that opens the apps, in minutes.
    var minimumMinutes = 2
    /// Daily limit only: minutes of the held apps allowed first.
    var dailyLimitMinutes: Int?
    /// Whether apps have been picked. The picks themselves are tokens in
    /// BlockKit, never here.
    var hasApps = false
    var createdAt = Date()

    /// Out of the box (Melvin, 2026-09-22): Chill, three passes a day, and a
    /// two minute session opens the apps.
    static func preset(_ kind: BlockerKind) -> Blocker {
        switch kind {
        case .mindfulDay:
            return Blocker(kind: kind, name: "Mindful day")
        case .mindfulMorning:
            return Blocker(kind: kind, name: "Mindful morning", window: .hours(start: 6 * 60, end: 10 * 60))
        case .windDown:
            return Blocker(kind: kind, name: "Wind down", window: .hours(start: 21 * 60, end: 24 * 60))
        case .focusHours:
            return Blocker(kind: kind, name: "Focus hours", weekdays: Set(2...6),
                           window: .hours(start: 9 * 60, end: 17 * 60))
        case .dailyLimit:
            return Blocker(kind: kind, name: "Daily limit", dailyLimitMinutes: 30)
        case .custom:
            return Blocker(kind: kind, name: "My blocker", window: .hours(start: 8 * 60, end: 12 * 60))
        }
    }

    /// The window that opens on the day of `date`, or nil if it does not run
    /// that day. A window belongs to the day it opens, even when it runs past
    /// midnight.
    func window(openingOnDayOf date: Date, calendar: Calendar = .current) -> DateInterval? {
        let day = calendar.startOfDay(for: date)
        guard weekdays.contains(calendar.component(.weekday, from: day)) else { return nil }
        switch window {
        case .allDay:
            guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return DateInterval(start: day, end: end)
        case .hours(let start, let end):
            let finish = end > start ? end : end + 24 * 60
            guard let open = calendar.date(byAdding: .minute, value: start, to: day),
                  let close = calendar.date(byAdding: .minute, value: finish, to: day) else { return nil }
            return DateInterval(start: open, end: close)
        }
    }

    /// The window holding `now`, if one is open. Checks yesterday's too,
    /// because a window that crossed midnight is still yesterday's.
    func openWindow(at now: Date, calendar: Calendar = .current) -> DateInterval? {
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let window = window(openingOnDayOf: day, calendar: calendar) else { continue }
            if window.start <= now && now < window.end { return window }
        }
        return nil
    }

    /// "All day, every day", "6 to 10, weekdays": the line under its name.
    func scheduleLine(calendar: Calendar = .current) -> String {
        let when: String
        switch window {
        case .allDay:
            when = dailyLimitMinutes.map { "After \($0) minutes a day" } ?? "All day"
        case .hours(let start, let end):
            when = "\(Self.clock(start)) to \(Self.clock(end))"
        }
        return "\(when), \(Self.days(weekdays))"
    }

    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        if m == 0 { return "midnight" }
        if m == 12 * 60 { return "noon" }
        let hour = m / 60, minute = m % 60
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return minute == 0 ? "\(h12) \(suffix)" : String(format: "%d:%02d %@", h12, minute, suffix)
    }

    static func days(_ days: Set<Int>) -> String {
        switch days {
        case Set(1...7): return "every day"
        case Set(2...6): return "weekdays"
        case [1, 7]: return "weekends"
        default:
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            // Monday first, the way people say a week.
            return [2, 3, 4, 5, 6, 7, 1].filter(days.contains).map { names[$0 - 1] }
                .joined(separator: ", ")
        }
    }
}

/// A "Not now": the apps opened for a few minutes, inside one window.
struct BlockPass: Codable, Equatable {
    var blockerID: UUID
    var start: Date
    var end: Date
    /// The window it was taken in, kept so the glow rule can price a window
    /// that closed without a session even after the blocker changed.
    var window: DateInterval
}

/// A session that opened a blocker's apps for the rest of one window.
struct BlockRelease: Codable, Equatable {
    var blockerID: UUID
    var windowStart: Date
    var at: Date
}

/// A daily limit that ran out.
struct BlockLimitHit: Codable, Equatable {
    var blockerID: UUID
    var day: Date
}

/// Everything Block remembers, in the App Group, shared by the app and its
/// extensions. Plain dates and ids only.
struct BlockState: Codable, Equatable {
    var blockers: [Blocker] = []
    var passes: [BlockPass] = []
    var releases: [BlockRelease] = []
    /// Taps on the shield's "Ask Otto", newest last.
    var asks: [Date] = []
    var limitHits: [BlockLimitHit] = []
    /// Otto's screens shown lately, newest last, so he never repeats himself.
    var recentInterventions: [String] = []
    /// The default Mindful day was created once; deleting it does not bring
    /// it back.
    var seededDefault = false
    /// When an Otto screen last opened, so an unanswered "Ask Otto" can be
    /// told apart from one already handled.
    var lastInterventionAt: Date?

    func blocker(_ id: UUID) -> Blocker? { blockers.first { $0.id == id } }
}

/// The rules, as pure functions over `BlockState`.
enum BlockRules {

    /// Whether `blocker` holds its apps at `now`: on, with apps, inside an
    /// open window, a daily limit that ran out if it is one, not released by
    /// a session in this window, and no "Not now" pass running.
    static func holds(_ blocker: Blocker, in state: BlockState, at now: Date,
                      calendar: Calendar = .current) -> Bool {
        guard blocker.isOn, blocker.hasApps,
              let window = blocker.openWindow(at: now, calendar: calendar) else { return false }
        if blocker.dailyLimitMinutes != nil {
            let today = calendar.startOfDay(for: now)
            guard state.limitHits.contains(where: { $0.blockerID == blocker.id && $0.day == today })
            else { return false }
        }
        if released(blocker.id, window: window, in: state) { return false }
        if activePass(blocker.id, in: state, at: now) != nil { return false }
        return true
    }

    static func released(_ id: UUID, window: DateInterval, in state: BlockState) -> Bool {
        state.releases.contains { $0.blockerID == id && $0.windowStart == window.start }
    }

    static func activePass(_ id: UUID, in state: BlockState, at now: Date) -> BlockPass? {
        state.passes.last { $0.blockerID == id && $0.start <= now && now < $0.end }
    }

    /// Blockers holding right now.
    static func holding(_ state: BlockState, at now: Date, calendar: Calendar = .current) -> [Blocker] {
        state.blockers.filter { holds($0, in: state, at: now, calendar: calendar) }
    }

    /// Passes left today. nil is no limit; Strict has none.
    static func passesLeft(_ blocker: Blocker, in state: BlockState, at now: Date,
                           calendar: Calendar = .current) -> Int? {
        if blocker.strictness == .strict { return 0 }
        guard let perDay = blocker.passesPerDay else { return nil }
        let used = state.passes.filter {
            $0.blockerID == blocker.id && calendar.isDate($0.start, inSameDayAs: now)
        }.count
        return max(0, perDay - used)
    }

    static func canTakePass(_ blocker: Blocker, in state: BlockState, at now: Date,
                            calendar: Calendar = .current) -> Bool {
        guard blocker.strictness != .strict else { return false }
        return (passesLeft(blocker, in: state, at: now, calendar: calendar) ?? 1) > 0
    }

    /// "Not now" for `minutes`: a pass for every holding blocker that has one
    /// left. Returns the ids that opened; Strict ones and spent ones stay held.
    @discardableResult
    static func takePass(minutes: Int, in state: inout BlockState, at now: Date,
                         calendar: Calendar = .current) -> [UUID] {
        var opened: [UUID] = []
        for blocker in holding(state, at: now, calendar: calendar)
        where canTakePass(blocker, in: state, at: now, calendar: calendar) {
            guard let window = blocker.openWindow(at: now, calendar: calendar) else { continue }
            let end = min(now.addingTimeInterval(TimeInterval(minutes * 60)), window.end)
            state.passes.append(BlockPass(blockerID: blocker.id, start: now, end: end, window: window))
            opened.append(blocker.id)
        }
        return opened
    }

    /// A session ended at `end`, lasting `durationSec`. Every blocker whose
    /// window holds the session, and whose shortest counting session it
    /// meets, is released for the rest of that window (Melvin, 2026-09-22:
    /// the window, not the day, so two windows mean two sessions). A window
    /// holds a session that started or ended inside it. Idempotent.
    @discardableResult
    static func recordSession(endingAt end: Date, durationSec: Int, in state: inout BlockState,
                              calendar: Calendar = .current) -> [UUID] {
        let start = end.addingTimeInterval(-TimeInterval(durationSec))
        var released: [UUID] = []
        for blocker in state.blockers where durationSec >= blocker.minimumMinutes * 60 {
            let window = blocker.openWindow(at: end, calendar: calendar)
                ?? blocker.openWindow(at: start, calendar: calendar)
            guard let window, !BlockRules.released(blocker.id, window: window, in: state) else { continue }
            state.releases.append(BlockRelease(blockerID: blocker.id, windowStart: window.start, at: end))
            released.append(blocker.id)
        }
        return released
    }

    /// A daily limit ran out today.
    static func recordLimitHit(_ id: UUID, at now: Date, in state: inout BlockState,
                               calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: now)
        guard !state.limitHits.contains(where: { $0.blockerID == id && $0.day == day }) else { return }
        state.limitHits.append(BlockLimitHit(blockerID: id, day: day))
    }

    /// The windows Otto was told "Not now" in that no session released, for
    /// the glow rule (`OttoAura.level(from:notNow:)`, which prices only the
    /// ones that have closed). One per window, however many passes it had.
    static func notNowWindows(_ state: BlockState) -> [DateInterval] {
        var seen = Set<String>()
        var windows: [DateInterval] = []
        for pass in state.passes {
            let key = "\(pass.blockerID)|\(pass.window.start.timeIntervalSinceReferenceDate)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            if released(pass.blockerID, window: pass.window, in: state) { continue }
            windows.append(pass.window)
        }
        return windows
    }

    /// Forgets what no rule reads any more: older than `days`.
    static func prune(_ state: inout BlockState, now: Date, days: Int = 45) {
        let cutoff = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        state.passes.removeAll { $0.end < cutoff }
        state.releases.removeAll { $0.at < cutoff }
        state.asks.removeAll { $0 < cutoff }
        state.limitHits.removeAll { $0.day < cutoff }
        if state.recentInterventions.count > 12 {
            state.recentInterventions.removeFirst(state.recentInterventions.count - 12)
        }
    }

    /// An "Ask Otto" newer than the last Otto screen: the person tapped the
    /// shield and has not been met yet. Opening 808 by hand then shows Otto,
    /// in case the notification never arrived.
    static func unansweredAsk(_ state: BlockState, at now: Date, within seconds: TimeInterval = 180) -> Bool {
        guard let ask = state.asks.last, now.timeIntervalSince(ask) < seconds else { return false }
        guard let shown = state.lastInterventionAt else { return true }
        return shown < ask
    }
}
