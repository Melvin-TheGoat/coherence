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

enum BlockerKind: String, Codable, CaseIterable {
    case mindfulDay, mindfulMorning, windDown, focusHours, dailyLimit, custom

    /// What a blocker of this kind draws until somebody picks another.
    var defaultSymbol: String {
        switch self {
        case .mindfulDay: return "sun.max.fill"
        case .mindfulMorning: return "sunrise.fill"
        case .windDown: return "moon.stars.fill"
        case .focusHours: return "briefcase.fill"
        case .dailyLimit: return "hourglass"
        case .custom: return "hand.raised.fill"
        }
    }
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
    /// Daily limit only: minutes of the held apps allowed first.
    var dailyLimitMinutes: Int?
    /// Whether apps have been picked. The picks themselves are tokens in
    /// BlockKit, never here.
    var hasApps = false
    var createdAt = Date()
    /// The SF Symbol drawn in the blocker's circle, picked under the pencil
    /// (Aziz, 2026-09-22, from Brainrot's editor). nil draws the kind's own,
    /// which is what every blocker saved before this field existed shows.
    var symbol: String?
    /// "From 8 pm until I meditate" (Aziz, 2026-09-28): a Custom window whose
    /// only end is a session, or midnight at the latest. Stored as hours
    /// running to midnight (every window already opens on a session), and
    /// marked so it reads back as what was chosen rather than as "8 pm to
    /// midnight". nil on every blocker saved before it.
    var untilSession: Bool?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, isOn, weekdays, window
        case dailyLimitMinutes, hasApps, createdAt, symbol, untilSession
    }

    /// The symbol to draw: the one picked, else the kind's.
    var displaySymbol: String { symbol ?? kind.defaultSymbol }

    /// The shortest session that opens held apps, for every blocker (Aziz,
    /// 2026-09-22). It was a per-blocker setting beside strictness and a
    /// daily pass limit; all three left the editor, and blockers saved with
    /// them simply ignore the old keys.
    static let sessionMinutes = 5

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
            // An end at or before the start is tomorrow's clock time.
            guard let endDay = end > start ? day : calendar.date(byAdding: .day, value: 1, to: day),
                  let open = Self.clockTime(start, on: day, calendar: calendar),
                  let close = Self.clockTime(end, on: endDay, calendar: calendar),
                  close > open else { return nil }
            return DateInterval(start: open, end: close)
        }
    }

    /// `minutes` past midnight as a wall-clock time on `day`; 1440 is the
    /// next midnight. **By clock time, not by adding minutes to midnight**:
    /// on a daylight saving day that arithmetic put a 6:00 start at 7:00,
    /// while Screen Time wakes the monitor at 6:00 on the clock.
    static func clockTime(_ minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        if minutes >= 24 * 60 {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
        }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    /// Screen Time refuses an interval shorter than fifteen minutes.
    static let shortestWindowMinutes = 15

    /// Why Screen Time would refuse these hours, in words, or nil.
    var windowProblem: String? {
        guard case .hours(let start, let end) = window else { return nil }
        // Midnight to the next midnight is the whole day, not an empty
        // window: "From midnight until I meditate" is saved that way.
        if end - start == 1440 { return nil }
        if start % 1440 == end % 1440 { return "Pick an end time after the start." }
        let length = end > start ? end - start : end + 1440 - start
        if length < Self.shortestWindowMinutes { return "A window needs at least 15 minutes." }
        return nil
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
            when = untilSession == true
                ? "From \(Self.clock(start)) until you meditate"
                : "\(Self.clock(start)) to \(Self.clock(end))"
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

    enum CodingKeys: String, CodingKey {
        case blockers, passes, releases, asks, limitHits, recentInterventions
        case seededDefault, lastInterventionAt
    }

    func blocker(_ id: UUID) -> Blocker? { blockers.first { $0.id == id } }
}

// MARK: - Decoding that survives the next release

// **Every field is optional on the way in** (the review of 2026-09-22):
// synthesized Codable fails the whole state when one field is missing or new,
// the load then returned an empty state, and the next save wrote it over the
// person's blockers while their apps stayed shielded. A missing field takes
// its default; an unknown kind reads as a custom blocker.

extension Blocker {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decodeIfPresent(BlockerKind.self, forKey: .kind)) ?? .custom
        self = Blocker.preset(kind)
        if let v = try? c.decodeIfPresent(UUID.self, forKey: .id) { id = v }
        if let v = try? c.decodeIfPresent(String.self, forKey: .name) { name = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .isOn) { isOn = v }
        if let v = try? c.decodeIfPresent(Set<Int>.self, forKey: .weekdays), !v.isEmpty { weekdays = v }
        if let v = try? c.decodeIfPresent(BlockWindow.self, forKey: .window) { window = v }
        // A missing limit is NO limit, whatever the kind: the encoder below
        // writes the key every time, and the synthesized one it replaced
        // left it out when nil, so a limit cleared in the editor used to come
        // back as the Daily limit preset's 30 minutes.
        dailyLimitMinutes = try? c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .hasApps) { hasApps = v }
        if let v = try? c.decodeIfPresent(Date.self, forKey: .createdAt) { createdAt = v }
        symbol = try? c.decodeIfPresent(String.self, forKey: .symbol)
        untilSession = try? c.decodeIfPresent(Bool.self, forKey: .untilSession)
    }

    /// Writes `dailyLimitMinutes` even when it is nil, so "no limit" is on
    /// the record rather than inferred from a missing key.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(isOn, forKey: .isOn)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(window, forKey: .window)
        if let dailyLimitMinutes {
            try c.encode(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        } else {
            try c.encodeNil(forKey: .dailyLimitMinutes)
        }
        try c.encode(hasApps, forKey: .hasApps)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        try c.encodeIfPresent(untilSession, forKey: .untilSession)
    }
}

extension BlockState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        blockers = (try? c.decodeIfPresent([Blocker].self, forKey: .blockers)) ?? []
        passes = (try? c.decodeIfPresent([BlockPass].self, forKey: .passes)) ?? []
        releases = (try? c.decodeIfPresent([BlockRelease].self, forKey: .releases)) ?? []
        asks = (try? c.decodeIfPresent([Date].self, forKey: .asks)) ?? []
        limitHits = (try? c.decodeIfPresent([BlockLimitHit].self, forKey: .limitHits)) ?? []
        recentInterventions = (try? c.decodeIfPresent([String].self, forKey: .recentInterventions)) ?? []
        seededDefault = (try? c.decodeIfPresent(Bool.self, forKey: .seededDefault)) ?? !blockers.isEmpty
        lastInterventionAt = try? c.decodeIfPresent(Date.self, forKey: .lastInterventionAt)
    }
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

    /// Matched by the window's start, or by the session landing inside the
    /// window, so a release survives the window being worked out again
    /// (a time zone change mid-window moves its start).
    static func released(_ id: UUID, window: DateInterval, in state: BlockState) -> Bool {
        state.releases.contains {
            $0.blockerID == id
                && ($0.windowStart == window.start || (window.start <= $0.at && $0.at < window.end))
        }
    }

    static func activePass(_ id: UUID, in state: BlockState, at now: Date) -> BlockPass? {
        state.passes.last { $0.blockerID == id && $0.start <= now && now < $0.end }
    }

    /// Blockers holding right now.
    static func holding(_ state: BlockState, at now: Date, calendar: Calendar = .current) -> [Blocker] {
        state.blockers.filter { holds($0, in: state, at: now, calendar: calendar) }
    }

    /// "Not now" for `minutes`: every holding blocker opens for that long.
    /// There is no daily limit and no strict mode (Aziz, 2026-09-22): a
    /// "Not now" costs glow when its window closes with no session, and that
    /// is the whole price. Returns the ids that opened.
    @discardableResult
    static func takePass(minutes: Int, in state: inout BlockState, at now: Date,
                         calendar: Calendar = .current) -> [UUID] {
        var opened: [UUID] = []
        for blocker in holding(state, at: now, calendar: calendar) {
            guard let window = blocker.openWindow(at: now, calendar: calendar) else { continue }
            let end = wholeSecond(min(now.addingTimeInterval(TimeInterval(minutes * 60)), window.end))
            state.passes.append(BlockPass(blockerID: blocker.id, start: now, end: end, window: window))
            opened.append(blocker.id)
        }
        return opened
    }

    /// `date` rounded UP to a whole second. A pass ends on one, because
    /// Screen Time is told its end in whole seconds and truncates the rest:
    /// an end of 10:05:03.7 woke the monitor at 10:05:03, a hair before the
    /// pass had run out, so the apps stayed open until something else woke it.
    static func wholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.up))
    }

    /// A session ended at `end`, lasting `durationSec`. Every blocker whose
    /// window holds the session is released, when the session lasted at least
    /// `Blocker.sessionMinutes`, for the rest of that window (Melvin, 2026-09-22:
    /// the window, not the day, so two windows mean two sessions). A window
    /// holds a session that started or ended inside it. Idempotent.
    @discardableResult
    static func recordSession(endingAt end: Date, durationSec: Int, in state: inout BlockState,
                              calendar: Calendar = .current) -> [UUID] {
        let start = end.addingTimeInterval(-TimeInterval(durationSec))
        var released: [UUID] = []
        guard durationSec >= Blocker.sessionMinutes * 60 else { return [] }
        for blocker in state.blockers {
            let window = blocker.openWindow(at: end, calendar: calendar)
                ?? blocker.openWindow(at: start, calendar: calendar)
            guard let window, !BlockRules.released(blocker.id, window: window, in: state) else { continue }
            state.releases.append(BlockRelease(blockerID: blocker.id, windowStart: window.start, at: end))
            released.append(blocker.id)
        }
        return released
    }

    /// Takes back every opening whose session is gone (Aziz, 2026-10-01). A
    /// session deleted from its page, or by deleting the account, used to
    /// leave its release behind: the apps stayed open all day, the card said
    /// "Open, you meditated", and the app held no session at all. `ends` is
    /// when every session still stored ended; only releases since `since`
    /// are judged, the span the caller's list is complete for. Returns
    /// whether anything was taken back.
    @discardableResult
    static func forgetReleases(withoutSessionsEnding ends: [Date], since: Date,
                               in state: inout BlockState) -> Bool {
        let before = state.releases.count
        state.releases.removeAll { release in
            release.at >= since && !ends.contains { abs($0.timeIntervalSince(release.at)) < 2 }
        }
        return state.releases.count != before
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

    /// Forgets what no rule reads any more.
    ///
    /// **Passes and releases are kept for two years, not weeks**: Otto's glow
    /// replays the whole history, so dropping an old "Not now" would change
    /// today's glow after the fact. They are a few bytes each. Asks and
    /// daily-limit hits only matter for a day.
    static func prune(_ state: inout BlockState, now: Date, days: Int = 45) {
        let cutoff = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let history = now.addingTimeInterval(-730 * 86_400)
        state.passes.removeAll { $0.end < history }
        state.releases.removeAll { $0.at < history }
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

/// What a held app's shield says and how it looks (Aziz, 2026-10-06).
/// Each time a shield appears it picks one line and one colour, so the
/// blocker reads like Otto talking rather than a wall, and no two screenshots
/// of it look the same. The shield can only be one solid colour, an icon,
/// a title, a subtitle and two buttons (Apple's limit), so the colour and the
/// words carry all of it. Mockup: `mockups/shield-backgrounds.html`.
///
/// `{app}` is the held app's name. Every line carries an emoji (Aziz).
enum ShieldLines {
    struct Line: Equatable {
        let title: String
        let subtitle: String
    }

    static let all: [Line] = [
        Line(title: "bruh. 🤦", subtitle: "{app}? Already? You haven't even meditated today 😑"),
        Line(title: "caught in 4k 📸", subtitle: "Otto saw that. Meditate first, {app} later."),
        Line(title: "Are you for real? 🤨", subtitle: "Meditate first. {app} will be there once you're done."),
        Line(title: "the audacity 😤", subtitle: "Opening {app} before meditating? I'm not liking this 😒"),
        Line(title: "nah. not yet. ✋", subtitle: "Otto's holding {app} until you meditate."),
        Line(title: "ok but did you meditate tho 👀", subtitle: "Otto's holding {app} until you do."),
        Line(title: "{app} can wait 🧘", subtitle: "Your meditation can't. Meditate, then you'll feel so much better."),
        Line(title: "Otto said no 🙅", subtitle: "He'll open {app} once you've meditated."),
        Line(title: "we're not doing this rn 🚫", subtitle: "Meditate with Otto, then {app}'s back."),
        Line(title: "zen first, scroll later 🌿", subtitle: "Otto's holding {app} for you 🔒"),
        Line(title: "touch grass first 🌱", subtitle: "Five quiet minutes, then scroll all you want."),
        Line(title: "plot twist: you meditate first 🤯", subtitle: "Then {app} unlocks. Otto's rules."),
        Line(title: "not the doom scroll 💀", subtitle: "Five minutes of calm first. Otto's waiting."),
    ]

    /// One solid background with text and button colours that stay readable
    /// on it, as 0xRRGGBB.
    struct Palette: Equatable {
        let background: UInt32
        let text: UInt32
        let soft: UInt32
        let softAlpha: Double
        let button: UInt32
        let buttonText: UInt32
    }

    static let palettes: [Palette] = [
        Palette(background: 0x1E2440, text: 0xF3EAD8, soft: 0xF3EAD8, softAlpha: 0.72, button: 0xF0C47B, buttonText: 0x2B2117), // night valley
        Palette(background: 0x111111, text: 0xFFFFFF, soft: 0xFFFFFF, softAlpha: 0.65, button: 0xF0C47B, buttonText: 0x1A1206), // midnight black
        Palette(background: 0x3B2A6B, text: 0xFFFFFF, soft: 0xFFFFFF, softAlpha: 0.75, button: 0xF6C66B, buttonText: 0x2B2117), // deep purple
        Palette(background: 0x2F6FD6, text: 0xFFFFFF, soft: 0xFFFFFF, softAlpha: 0.80, button: 0xFFFFFF, buttonText: 0x1F4E9C), // ocean blue
        Palette(background: 0x8EC3EA, text: 0x2B2117, soft: 0x2B2117, softAlpha: 0.70, button: 0xFFFFFF, buttonText: 0x1F4E70), // sky
        Palette(background: 0x6FA35B, text: 0xFFFFFF, soft: 0xFFFFFF, softAlpha: 0.85, button: 0xFFF6E6, buttonText: 0x2E4A22), // meadow
        Palette(background: 0xF0B44C, text: 0x2B2117, soft: 0x2B2117, softAlpha: 0.72, button: 0x2B2117, buttonText: 0xFFF6E6), // otto gold
        Palette(background: 0xF2803A, text: 0xFFFFFF, soft: 0xFFFFFF, softAlpha: 0.85, button: 0xFFFFFF, buttonText: 0xB5521A), // sunset orange
        Palette(background: 0xEE6B4D, text: 0xFFFFFF, soft: 0xFFFFFF, softAlpha: 0.85, button: 0xFFFFFF, buttonText: 0xC9472B), // alarm coral
        Palette(background: 0xF27DB0, text: 0xFFFFFF, soft: 0xFFFFFF, softAlpha: 0.88, button: 0xFFFFFF, buttonText: 0xB33E73), // bubblegum pink
    ]

    /// `{app}` filled with the held app's name, or "this app" when the shield
    /// is not told it; capitalised when it opens the sentence.
    static func fill(_ text: String, app: String?) -> String {
        let name = app?.isEmpty == false ? app! : "this app"
        var out = text.replacingOccurrences(of: "{app}", with: name)
        if text.hasPrefix("{app}"), let first = out.first {
            out = first.uppercased() + out.dropFirst()
        }
        return out
    }

    /// A fresh pick, never the line or colour just shown.
    static func next(after previous: (line: Int, palette: Int)?,
                     random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> (line: Int, palette: Int) {
        func draw(_ count: Int, avoiding old: Int?) -> Int {
            guard let old, count > 1 else { return random(count) }
            let r = random(count - 1)
            return r >= old ? r + 1 : r
        }
        return (draw(all.count, avoiding: previous?.line),
                draw(palettes.count, avoiding: previous?.palette))
    }
}
