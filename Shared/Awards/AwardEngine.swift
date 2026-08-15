import Foundation

/// Decides which awards a history has earned. Pure Foundation, no SwiftData,
/// no UI, so every rule is testable without a device.
///
/// Every rule asks **"did this ever happen"** rather than "is this true now".
/// That is what makes an award permanent, and it is why a broken streak cannot
/// take one back.
public enum AwardEngine {

    /// The only facts a rule needs. Callers flatten Session + MeditationStats
    /// into this so the engine never learns about storage.
    public struct SessionFact {
        public let startedAt: Date
        public let durationSec: Int
        public let overallScore: Double?

        public init(startedAt: Date, durationSec: Int, overallScore: Double?) {
            self.startedAt = startedAt
            self.durationSec = durationSec
            self.overallScore = overallScore
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
    public static func evaluate(sessions: [SessionFact],
                                accountCreatedAt: Date?,
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

            default:
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

    /// Consecutive practised days, collapsed from session timestamps. Two
    /// sessions on one day are one day, which is the same rule the streak
    /// headline uses.
    static func streakRuns(_ dates: [Date], calendar: Calendar) -> [Run] {
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        guard !days.isEmpty else { return [] }

        var runs: [Run] = []
        var current: [Date] = [days[0]]
        for day in days.dropFirst() {
            let previous = current[current.count - 1]
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap == 1 {
                current.append(day)
            } else {
                runs.append(Run(dayDates: current))
                current = [day]
            }
        }
        runs.append(Run(dayDates: current))
        return runs
    }

    /// The run still alive today or yesterday, matching the streak headline's
    /// grace: practising yesterday and not yet today is still a live streak.
    static func currentStreakLength(_ runs: [Run], calendar: Calendar) -> Int {
        guard let last = runs.last, let end = last.dayDates.last else { return 0 }
        let today = calendar.startOfDay(for: Date())
        let gap = calendar.dateComponents([.day], from: end, to: today).day ?? 0
        return gap <= 1 ? last.length : 0
    }

    private static func scoreThreshold(_ id: String) -> Double? {
        guard id.hasPrefix("score"), let n = Int(id.dropFirst("score".count)) else { return nil }
        return Double(n) / 100
    }

    private static func minuteThreshold(_ id: String) -> Int? {
        guard id.hasPrefix("min"), let n = Int(id.dropFirst("min".count)) else { return nil }
        return n
    }
}
