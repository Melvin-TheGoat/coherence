import Foundation

/// Which onboarding answers reach usage analytics, and in what shape
/// (Melvin, 2026-10-13: "I want to get a sense for our customer profile").
///
/// Until this build no answer left the phone; only the screen that was left
/// did. Now each question below sends its answer with the `onboarding_step`
/// it already sent, and the same value lands on the anonymous PostHog person,
/// so anything can be split by it (paywall conversion by goal, say). Sent as
/// the screen is LEFT, so people who stop halfway are counted too.
///
/// **The list is closed, and so is what stays out:**
/// - In: goals, what gets in the way, role, age range, how often they
///   meditate, whether they tried before, when quiet minutes fit, and the
///   mind profile type (Melvin: "leave mind profile in").
/// - Out: the stress answer and the "mind somewhere else" slider. Self-rated
///   stress is the kind of thing the privacy policy's consumer-health-data
///   section covers, and sending it would pull PostHog into it. The mind
///   profile is derived partly from stress, but only its TYPE is sent, never
///   the stress answer or the two bar positions.
/// - Out, always: anything typed (the "Something else" goal's text, the name,
///   the username). The analytics rule is no free text.
///
/// Values are the enums' raw values (`lessStressed`, `deskJob`), not their
/// labels, so a copy change cannot split one answer into two in the data.
/// The analytics sheet turns them back into words. `OnboardingAnswerReportTests`
/// pins all of it.
public enum OnboardingAnswerReport {

    /// Property names. One prefix so they group together in PostHog.
    public enum Key {
        public static let goals = "onboarding_goals"
        public static let obstacles = "onboarding_obstacles"
        public static let role = "onboarding_role"
        public static let quietTime = "onboarding_quiet_time"
        public static let habitHistory = "onboarding_habit_history"
        public static let age = "onboarding_age"
        public static let frequency = "onboarding_frequency"
        public static let mindProfile = "onboarding_mind_profile"

        public static let all = [goals, obstacles, role, quietTime, habitHistory,
                                 age, frequency, mindProfile]
    }

    /// The answer the screen with this step id collected, as properties, or
    /// empty for a screen whose answer is never sent (or was left unanswered).
    /// `step` is the routing id `onboarding_step` already carries
    /// (`String(describing: Step)`).
    public static func properties(forStep step: String, answers a: OnboardingAnswers) -> [String: Any] {
        switch step {
        case "motivation":
            // Many can be true at once. Sorted, so the same picks always
            // read the same.
            let goals = a.motivations.map(\.rawValue).sorted()
            return goals.isEmpty ? [:] : [Key.goals: goals]
        case "obstacles":
            let obstacles = (a.obstacles ?? []).map(\.rawValue).sorted()
            return obstacles.isEmpty ? [:] : [Key.obstacles: obstacles]
        case "role":
            return a.role.map { [Key.role: $0.rawValue] } ?? [:]
        case "quietTime":
            return a.quietTime.map { [Key.quietTime: $0.rawValue] } ?? [:]
        case "habitHistory":
            return a.habitHistory.map { [Key.habitHistory: $0.rawValue] } ?? [:]
        case "age":
            // Any stored format ("25–34" from an older resume record) is
            // sent as today's label, so one bracket is one value.
            return AgeRange(stored: a.ageBracket).map { [Key.age: $0.rawValue] } ?? [:]
        case "baseline":
            return a.currentFrequency.map { [Key.frequency: $0.rawValue] } ?? [:]
        case "mindProfile":
            return [Key.mindProfile: MindProfile.of(a).rawValue]
        default:
            return [:]
        }
    }
}
