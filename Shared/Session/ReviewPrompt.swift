import Foundation

/// When to ask for an App Store rating. Pure, so the rule is testable.
///
/// **The moments** (Melvin, 2026-10-15: "after they complete their first
/// meditation ... a couple other places, it shouldn't be too persistent but
/// definitely we wanna get our ratings up a lot more"). Each is a happy
/// moment the person has just finished, and each is asked once:
/// - `firstSession`: their first completed meditation.
/// - `weekStreak`: the first time their streak reaches seven days.
/// - `later`: after that, again every `laterGapSec` (about four months) to
///   someone still meditating, which is the only kind of person who reaches
///   the hook.
/// The ask is made on Home once the session's reward, any award and its page
/// have closed (`ContentView`'s `QuietHomeHooks`), never during a sit,
/// onboarding, the tour or a sheet.
///
/// **Never two asks within `minGapSec`.** A moment earned inside the gap is
/// owed, not lost: it is asked after the next session once the gap has
/// passed. A moment earned before this rule existed (a member who already
/// had a seven-day streak) is covered by the same single ask as the first
/// session, so nobody is asked twice for things that happened long ago.
///
/// **Unconditional on how the session went, and it must stay that way.**
/// Routing only happy users to Apple's sheet is ratings manipulation and a
/// live App Review rejection (the 2026-08-11 compliance pass removed exactly
/// that). Nothing here takes a score, a verdict or a sentiment, and
/// `ReviewPromptTests` pins the signature. Apple's own sheet also caps
/// itself at three showings per 365 days whatever we ask.
enum ReviewPrompt {
    enum Moment: String, CaseIterable {
        case firstSession, weekStreak, later
    }

    /// One ask: the moment it is filed under, and every milestone it covers.
    struct Ask: Equatable {
        let moment: Moment
        let covers: Set<Moment>
    }

    /// No two asks closer than a week.
    static let minGapSec: TimeInterval = 7 * 24 * 3600
    /// The re-ask for regulars, once the milestones are behind them.
    static let laterGapSec: TimeInterval = 120 * 24 * 3600
    static let weekStreakDays = 7

    /// The App Store's write-a-review page, for a button a person taps
    /// (Settings, the founders' note). Apple's own sheet is for asks the
    /// app makes unprompted.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6806785308?action=write-review")!

    static let lastAskedKey = "reviewPrompt.lastAskedAt"
    static let askedMomentsKey = "reviewPrompt.askedMoments.v1"

    /// The ask owed right now, or nil.
    static func due(sessionCount: Int,
                    longestStreak: Int,
                    onboardingComplete: Bool,
                    asked: Set<Moment>,
                    lastAskedAt: Date?,
                    now: Date = Date()) -> Ask? {
        guard onboardingComplete, sessionCount >= 1 else { return nil }
        if let last = lastAskedAt, now.timeIntervalSince(last) < minGapSec { return nil }

        var earned: Set<Moment> = [.firstSession]
        if longestStreak >= weekStreakDays { earned.insert(.weekStreak) }
        let owed = earned.subtracting(asked)
        if !owed.isEmpty {
            // The biggest thing they have done names the ask.
            return Ask(moment: owed.contains(.weekStreak) ? .weekStreak : .firstSession, covers: owed)
        }
        if let last = lastAskedAt, now.timeIntervalSince(last) >= laterGapSec {
            return Ask(moment: .later, covers: [])
        }
        return nil
    }

    // MARK: - What this phone has asked

    static func askedMoments(_ defaults: UserDefaults = .standard) -> Set<Moment> {
        Set((defaults.stringArray(forKey: askedMomentsKey) ?? []).compactMap(Moment.init(rawValue:)))
    }

    static func lastAskedAt(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastAskedKey) as? Date
    }

    static func record(_ ask: Ask, now: Date = Date(), _ defaults: UserDefaults = .standard) {
        let all = askedMoments(defaults).union(ask.covers)
        defaults.set(all.map(\.rawValue).sorted(), forKey: askedMomentsKey)
        defaults.set(now, forKey: lastAskedKey)
    }
}
