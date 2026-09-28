import Foundation

/// Decides which awards a history has earned. Pure Foundation, no SwiftData,
/// no UI, so every rule is testable without a device.
///
/// Every rule asks **"did this ever happen"** rather than "is this true now".
/// That is what makes an award permanent, and it is why a broken streak cannot
/// take one back.
public enum AwardEngine {

    /// The only facts a rule needs. Callers flatten Session + MeditationStats
    /// (+ SessionReflection + SessionPhoto, since 2026-09-28) into this so the
    /// engine never learns about storage. See `AwardFacts.build`.
    public struct SessionFact {
        public let startedAt: Date
        public let durationSec: Int
        public let overallScore: Double?
        /// Typed in after the fact (`Session.isLogged`, "Record one"),
        /// rather than timed inside the app in real time. Counts toward
        /// totals, counts and streaks exactly like any other session, but
        /// never toward a single session's length or its time of day:
        /// nothing measured either of those for a logged sit.
        public let isLogged: Bool
        /// `Session.mode`: "silence", "guided", "nature", or "frequency".
        public let mode: String
        /// `Session.frequencyID`: the specific sound preset played, if any.
        public let soundID: String?
        /// The session's `SessionReflection.technique`, if one was logged.
        public let technique: String?
        /// The session's `SessionReflection.rating`, if it was rated.
        public let rating: Int?
        /// Whether a private or shared note was written for this session.
        public let hasNote: Bool
        /// Whether a photo or video was attached to this session.
        public let hasPhoto: Bool

        public init(startedAt: Date, durationSec: Int, overallScore: Double?,
                    isLogged: Bool = false, mode: String = "silence", soundID: String? = nil,
                    technique: String? = nil, rating: Int? = nil,
                    hasNote: Bool = false, hasPhoto: Bool = false) {
            self.startedAt = startedAt
            self.durationSec = durationSec
            self.overallScore = overallScore
            self.isLogged = isLogged
            self.mode = mode
            self.soundID = soundID
            self.technique = technique
            self.rating = rating
            self.hasNote = hasNote
            self.hasPhoto = hasPhoto
        }
    }

    public struct Earned: Identifiable, Hashable {
        public let award: Award
        /// When the condition first became true, which is the date of the
        /// session that earned it rather than the day it was noticed.
        public let earnedAt: Date?
        /// 0 to 1 toward the threshold. 1 once earned.
        public let progress: Double
        /// "7/10" style, only where a number means something.
        public let progressText: String?

        public var id: String { award.id }
        public var isEarned: Bool { earnedAt != nil }
    }

    /// - Parameter accountCreatedAt: when the user row was made. The signup
    ///   award is the one thing not derived from a session.
    /// - Parameter friendBroughtAt: when the first invited friend sat their
    ///   first session (`Preferences.evidenceGrantSince`). The second thing
    ///   not derived from a session, and still something done, not given.
    public static func evaluate(sessions: [SessionFact],
                                accountCreatedAt: Date?,
                                friendBroughtAt: Date? = nil,
                                calendar: Calendar = .current) -> [Earned] {
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        let runs = streakRuns(ordered.map(\.startedAt), calendar: calendar)

        return Award.all.map { award in
            switch award.id {
            case "firstStep":
                return Earned(award: award, earnedAt: accountCreatedAt,
                              progress: accountCreatedAt == nil ? 0 : 1,
                              progressText: nil)

            case "firstSession":
                return Earned(award: award, earnedAt: ordered.first?.startedAt,
                              progress: ordered.isEmpty ? 0 : 1, progressText: nil)

            case "friendBrought":
                return Earned(award: award, earnedAt: friendBroughtAt,
                              progress: friendBroughtAt == nil ? 0 : 1, progressText: nil)

            default:
                if let special = specialEarned(award, ordered: ordered, calendar: calendar) {
                    return special
                }
                if let days = award.streakDays {
                    // The date the run first reached `days`, not the run's end:
                    // you earned the ten-day award on day ten, not on day forty.
                    let hit = runs.first { $0.length >= days }
                        .map { $0.dayDates[days - 1] }
                    let current = currentStreakLength(runs, calendar: calendar)
                    return Earned(award: award, earnedAt: hit,
                                  progress: hit != nil ? 1
                                          : min(1, Double(current) / Double(days)),
                                  progressText: hit != nil ? nil : "\(current)/\(days)")
                }
                if let threshold = scoreThreshold(award.id) {
                    let hit = ordered.first { ($0.overallScore ?? 0) >= threshold }
                    let best = ordered.compactMap(\.overallScore).max() ?? 0
                    return Earned(award: award, earnedAt: hit?.startedAt,
                                  progress: hit != nil ? 1 : min(1, best / threshold),
                                  progressText: hit != nil ? nil
                                      : "best \(Int((best * 100).rounded()))")
                }
                if let minutes = minuteThreshold(award.id) {
                    let seconds = minutes * 60
                    let hit = ordered.first { $0.durationSec >= seconds }
                    let longest = ordered.map(\.durationSec).max() ?? 0
                    return Earned(award: award, earnedAt: hit?.startedAt,
                                  progress: hit != nil ? 1
                                          : min(1, Double(longest) / Double(seconds)),
                                  progressText: hit != nil ? nil
                                      : "longest \(longest / 60) min")
                }
                // A single session's length, timed for real: unlike `min20`
                // etc above, a hand-logged sit is excluded, since nothing
                // measured how long it actually took.
                if let minutes = lengthThreshold(award.id) {
                    let seconds = minutes * 60
                    let real = ordered.filter { !$0.isLogged }
                    let hit = real.first { $0.durationSec >= seconds }
                    let longest = real.map(\.durationSec).max() ?? 0
                    return Earned(award: award, earnedAt: hit?.startedAt,
                                  progress: hit != nil ? 1
                                          : min(1, Double(longest) / Double(seconds)),
                                  progressText: hit != nil ? nil
                                      : "longest \(longest / 60) min")
                }
                // Total minutes ever sat, across every session including
                // hand-logged ones: a total, not a single sit's length.
                if let hours = totalHoursThreshold(award.id) {
                    let thresholdSec = hours * 3600
                    var total = 0
                    var hitDate: Date?
                    for fact in ordered {
                        total += fact.durationSec
                        if hitDate == nil && total >= thresholdSec { hitDate = fact.startedAt }
                    }
                    return Earned(award: award, earnedAt: hitDate,
                                  progress: hitDate != nil ? 1
                                          : min(1, Double(total) / Double(thresholdSec)),
                                  progressText: hitDate != nil ? nil
                                      : "\(total / 60)/\(hours * 60) min")
                }
                if let count = sessionCountThreshold(award.id) {
                    let hit = ordered.count >= count ? ordered[count - 1] : nil
                    return Earned(award: award, earnedAt: hit?.startedAt,
                                  progress: hit != nil ? 1
                                          : min(1, Double(ordered.count) / Double(count)),
                                  progressText: hit != nil ? nil
                                      : "\(ordered.count)/\(count)")
                }
                if let days = practicedDaysThreshold(award.id) {
                    let daySet = Set(ordered.map { calendar.startOfDay(for: $0.startedAt) }).sorted()
                    let hit = daySet.count >= days
                    return Earned(award: award, earnedAt: hit ? daySet[days - 1] : nil,
                                  progress: hit ? 1 : min(1, Double(daySet.count) / Double(days)),
                                  progressText: hit ? nil : "\(daySet.count)/\(days)")
                }
                return Earned(award: award, earnedAt: nil, progress: 0, progressText: nil)
            }
        }
        // Earned first, newest first within that; then locked in catalog order,
        // closest to earned first, so the shelf always shows what is reachable.
        .enumerated()
        .sorted { a, b in
            switch (a.element.earnedAt, b.element.earnedAt) {
            case let (l?, r?): return l > r
            case (_?, nil):    return true
            case (nil, _?):    return false
            default:
                if a.element.progress != b.element.progress {
                    return a.element.progress > b.element.progress
                }
                return a.offset < b.offset
            }
        }
        .map(\.element)
    }

    // MARK: - Streak runs

    struct Run {
        /// One date per practised day, ascending.
        let dayDates: [Date]
        var length: Int { dayDates.count }
    }

    /// Practised days collapsed into runs, by THE streak rule
    /// (`StreakCalculator.runs`, rest days included since 2026-09-15), so a
    /// streak award and the Home headline can never disagree about a run.
    static func streakRuns(_ dates: [Date], calendar: Calendar) -> [Run] {
        StreakCalculator.runs(from: dates, calendar: calendar).map { Run(dayDates: $0.days) }
    }

    /// The run still alive, matching the streak headline's grace exactly
    /// (yesterday, or a rest day carrying the run to today).
    static func currentStreakLength(_ runs: [Run], calendar: Calendar) -> Int {
        StreakCalculator.streak(from: runs.flatMap(\.dayDates), calendar: calendar).current
    }

    private static func scoreThreshold(_ id: String) -> Double? {
        guard id.hasPrefix("score"), let n = Int(id.dropFirst("score".count)) else { return nil }
        return Double(n) / 100
    }

    private static func minuteThreshold(_ id: String) -> Int? {
        guard id.hasPrefix("min"), let n = Int(id.dropFirst("min".count)) else { return nil }
        return n
    }

    private static func lengthThreshold(_ id: String) -> Int? {
        guard id.hasPrefix("length"), let n = Int(id.dropFirst("length".count)) else { return nil }
        return n
    }

    private static func totalHoursThreshold(_ id: String) -> Int? {
        guard id.hasPrefix("totalHours"), let n = Int(id.dropFirst("totalHours".count)) else { return nil }
        return n
    }

    private static func sessionCountThreshold(_ id: String) -> Int? {
        guard id.hasPrefix("sessions"), let n = Int(id.dropFirst("sessions".count)) else { return nil }
        return n
    }

    private static func practicedDaysThreshold(_ id: String) -> Int? {
        guard id.hasPrefix("practicedDays"), let n = Int(id.dropFirst("practicedDays".count)) else { return nil }
        return n
    }

    // MARK: - One-off rules

    /// Everything that doesn't fit a "prefix + number" parser above: distinct
    /// value counts, calendar-day patterns, and reflection facts. Kept apart
    /// so the parametrized checks above stay simple string parsers, and this
    /// stays a single place to look for "how is THIS one earned".
    private static func specialEarned(_ award: Award, ordered: [SessionFact],
                                      calendar: Calendar) -> Earned? {
        func real() -> [SessionFact] { ordered.filter { !$0.isLogged } }

        switch award.id {

        case "earlyBird", "lunchBreak", "eveningWindDown", "nightOwl":
            let test = timeOfDayTest(award.id)
            let hit = real().first { test(calendar.component(.hour, from: $0.startedAt)) }
            return Earned(award: award, earnedAt: hit?.startedAt,
                          progress: hit != nil ? 1 : 0, progressText: nil)

        case "allPartsOfDay":
            let sessions = real()
            let firsts = ["earlyBird", "lunchBreak", "eveningWindDown", "nightOwl"].map { id -> Date? in
                let test = timeOfDayTest(id)
                return sessions.first { test(calendar.component(.hour, from: $0.startedAt)) }?.startedAt
            }
            let known = firsts.compactMap { $0 }
            guard known.count == firsts.count else {
                return Earned(award: award, earnedAt: nil,
                              progress: Double(known.count) / Double(firsts.count), progressText: nil)
            }
            return Earned(award: award, earnedAt: known.max(), progress: 1, progressText: nil)

        case "soundExplorer":
            let pairs = ordered.compactMap { fact -> (Date, String)? in
                fact.soundID.map { (fact.startedAt, $0) }
            }
            let hitAt = dateOfNthDistinct(pairs, count: 3)
            return Earned(award: award, earnedAt: hitAt,
                          progress: hitAt != nil ? 1 : min(1, Double(Set(pairs.map(\.1)).count) / 3),
                          progressText: nil)

        case "techniqueVariety":
            let pairs = ordered.compactMap { fact -> (Date, String)? in
                fact.technique.map { (fact.startedAt, $0) }
            }
            let hitAt = dateOfNthDistinct(pairs, count: 3)
            return Earned(award: award, earnedAt: hitAt,
                          progress: hitAt != nil ? 1 : min(1, Double(Set(pairs.map(\.1)).count) / 3),
                          progressText: nil)

        case "guidedComplete":
            // A guided track is minutes long; 25 covers the shipped journey
            // with room for a session that ends a little early.
            let hit = ordered.first { $0.mode == "guided" && $0.durationSec >= 1500 }
            return Earned(award: award, earnedAt: hit?.startedAt,
                          progress: hit != nil ? 1 : 0, progressText: nil)

        case "sessionInSilence":
            // Not a hand-logged session: those default to "silence" because
            // the logging flow never asks about sound, so any one of them
            // would trivially earn this without anyone choosing silence
            // over a sound.
            let hit = real().first { $0.mode == "silence" }
            return Earned(award: award, earnedAt: hit?.startedAt,
                          progress: hit != nil ? 1 : 0, progressText: nil)

        case "sessionRated":
            let hit = ordered.first { $0.rating != nil }
            return Earned(award: award, earnedAt: hit?.startedAt,
                          progress: hit != nil ? 1 : 0, progressText: nil)

        case "wroteANote":
            let hit = ordered.first(where: \.hasNote)
            return Earned(award: award, earnedAt: hit?.startedAt,
                          progress: hit != nil ? 1 : 0, progressText: nil)

        case "addedPhoto":
            let hit = ordered.first(where: \.hasPhoto)
            return Earned(award: award, earnedAt: hit?.startedAt,
                          progress: hit != nil ? 1 : 0, progressText: nil)

        case "perfectWeek":
            let days = Set(ordered.map { calendar.startOfDay(for: $0.startedAt) })
            for start in days.sorted() {
                let window = (0...6).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                guard window.count == 7, window.allSatisfy({ days.contains($0) }) else { continue }
                return Earned(award: award, earnedAt: window.last, progress: 1, progressText: nil)
            }
            return Earned(award: award, earnedAt: nil, progress: 0, progressText: nil)

        case "multipleInADay":
            let byDay = Dictionary(grouping: ordered) { calendar.startOfDay(for: $0.startedAt) }
            let hitDay = byDay.filter { $0.value.count >= 2 }.keys.min()
            let earnedAt = hitDay.flatMap { day in
                byDay[day]?.sorted { $0.startedAt < $1.startedAt }.dropFirst().first?.startedAt
            }
            return Earned(award: award, earnedAt: earnedAt,
                          progress: earnedAt != nil ? 1 : 0, progressText: nil)

        case "cameBack":
            let days = Set(ordered.map { calendar.startOfDay(for: $0.startedAt) }).sorted()
            guard days.count > 1 else {
                return Earned(award: award, earnedAt: nil, progress: 0, progressText: nil)
            }
            for i in 1..<days.count {
                let gap = calendar.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
                if gap >= 7 {
                    return Earned(award: award, earnedAt: days[i], progress: 1, progressText: nil)
                }
            }
            return Earned(award: award, earnedAt: nil, progress: 0, progressText: nil)

        case "weekendWarrior":
            let days = Set(ordered.map { calendar.startOfDay(for: $0.startedAt) })
            for day in days.sorted() where calendar.component(.weekday, from: day) == 7 {
                guard let sunday = calendar.date(byAdding: .day, value: 1, to: day),
                      days.contains(sunday) else { continue }
                return Earned(award: award, earnedAt: sunday, progress: 1, progressText: nil)
            }
            return Earned(award: award, earnedAt: nil, progress: 0, progressText: nil)

        case "restDayContinued":
            for run in StreakCalculator.runs(from: ordered.map(\.startedAt), calendar: calendar) {
                guard let rest = run.restDays.first,
                      let continued = calendar.date(byAdding: .day, value: 1, to: rest) else { continue }
                return Earned(award: award, earnedAt: continued, progress: 1, progressText: nil)
            }
            return Earned(award: award, earnedAt: nil, progress: 0, progressText: nil)

        case "ottoSteady", "ottoBright", "ottoRadiant", "ottoNirvana":
            let stage: OttoAura.Stage = {
                switch award.id {
                case "ottoSteady":  return .steady
                case "ottoBright":  return .bright
                case "ottoRadiant": return .radiant
                default:            return .nirvana
                }
            }()
            let hit = OttoAura.dateStageFirstReached(
                stage,
                from: ordered.map { OttoAura.Sit(date: $0.startedAt, seconds: $0.durationSec) },
                calendar: calendar)
            return Earned(award: award, earnedAt: hit, progress: hit != nil ? 1 : 0, progressText: nil)

        default:
            return nil
        }
    }

    private static func timeOfDayTest(_ id: String) -> (Int) -> Bool {
        switch id {
        case "earlyBird":       return { (5..<8).contains($0) }
        case "lunchBreak":      return { (12..<14).contains($0) }
        case "eveningWindDown": return { (18..<21).contains($0) }
        default:                return { $0 >= 22 || $0 < 5 }   // nightOwl
        }
    }

    /// The date at which a chronological series of values first contained
    /// `count` distinct entries. Used for "tried N different sounds"-style
    /// variety awards.
    private static func dateOfNthDistinct(_ pairs: [(Date, String)], count: Int) -> Date? {
        var seen = Set<String>()
        for (date, value) in pairs.sorted(by: { $0.0 < $1.0 }) {
            seen.insert(value)
            if seen.count >= count { return date }
        }
        return nil
    }
}
