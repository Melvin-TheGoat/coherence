import Foundation

/// Where someone got to in onboarding, saved on every advance so closing the
/// app mid-flow resumes on the same screen instead of screen one.
///
/// Why it exists (PostHog, 2026-09-14): a stranger in Wednesbury answered
/// every question, reached the tour, left the app, came back two and a half
/// hours later to screen one, and used the "Already have an account?" link to
/// escape redoing twenty screens, which also skipped the paywall. Losing
/// progress pushes people out of the funnel; this keeps them in it.
///
/// Pure Foundation and step-agnostic (steps are stored by raw value), so it
/// lives in Shared/ and is testable without the app module. The view owns the
/// mapping from raw values to screens.
public struct OnboardingResume: Codable, Equatable {
    public var step: Int
    public var history: [Int]
    public var answers: OnboardingAnswers
    public var plan: String
    public var waitlistEmail: String
    public var planRating: Int?
    public var reminderAllowed: Bool
    public var savedAt: Date

    public init(step: Int, history: [Int], answers: OnboardingAnswers, plan: String,
                waitlistEmail: String, planRating: Int?, reminderAllowed: Bool, savedAt: Date = Date()) {
        self.step = step; self.history = history; self.answers = answers; self.plan = plan
        self.waitlistEmail = waitlistEmail; self.planRating = planRating
        self.reminderAllowed = reminderAllowed; self.savedAt = savedAt
    }

    public static let key = "onboarding.progress.v1"
    /// Older than this and it starts over: after two weeks the answers are
    /// stale and the person is effectively new.
    public static let maxAge: TimeInterval = 14 * 86_400

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public static func load(from defaults: UserDefaults = .standard, now: Date = Date()) -> OnboardingResume? {
        guard let data = defaults.data(forKey: key),
              let progress = try? JSONDecoder().decode(OnboardingResume.self, from: data) else { return nil }
        guard now.timeIntervalSince(progress.savedAt) < maxAge else {
            clear(from: defaults)
            return nil
        }
        return progress
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// The screen to reopen on. Some screens cannot be resumed because what
    /// they show died with the app (a live practice session, its results);
    /// those reopen on `fallback`, the screen that leads into them, and the
    /// history is trimmed to match so Back still makes sense.
    public func resumePoint(unresumable: Set<Int>, fallback: Int) -> (step: Int, history: [Int]) {
        guard unresumable.contains(step) else { return (step, history) }
        if let i = history.lastIndex(of: fallback) {
            return (fallback, Array(history[..<i]))
        }
        return (fallback, history.filter { !unresumable.contains($0) })
    }
}
