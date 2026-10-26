import Foundation

/// The founders' note: Melvin and Aziz thank a member, ask for anything they
/// would change, and ask for an App Store review (Melvin, 2026-10-26,
/// direction A of the "Founders' note" canvas). Pure, so the rule is
/// testable; `FoundersNoteView` draws it and Home's `QuietHomeHooks` opens it.
///
/// **When:** on Home, after a session the person ran (never one typed in by
/// hand) once they have run at least `minSessions`, when the session's
/// reward, any award and its page have closed. Once. "Maybe later", or a tap
/// outside it, brings it back ONE more time, at least `laterGapSec` after
/// the first showing; after that it never shows again. Writing a review or
/// telling us something ends it.
///
/// **Never on the same day as Apple's rating sheet** (`ratingClearSec`):
/// two asks for a review back to back read as nagging, and Apple's sheet
/// comes first because it is the one Apple asks apps to use.
///
/// **Unconditional on how the session went**, like `ReviewPrompt`: routing
/// only happy members to a review is ratings manipulation. Nothing here
/// takes a score, a rating or a sentiment.
enum FoundersNote {
    enum Answer: String, CaseIterable {
        /// "Write a review": the App Store's review page.
        case review
        /// "Tell us anything": an email to support.
        case feedback
        /// "Maybe later".
        case later
        /// A tap outside the note.
        case dismissed

        /// An answer that ends the note for good.
        var isFinal: Bool { self == .review || self == .feedback }
    }

    static let minSessions = 2
    static let laterGapSec: TimeInterval = 7 * 24 * 3600
    static let ratingClearSec: TimeInterval = 24 * 3600
    static let maxShowings = 2

    static let feedbackURL = URL(string: "mailto:support@meditate808.com?subject=808%20feedback")!

    static let shownKey = "foundersNote.shownAt.v1"
    static let doneKey = "foundersNote.done.v1"

    /// Whether the note opens now.
    static func due(sessionsRun: Int,
                    onboardingComplete: Bool,
                    shown: [Date],
                    done: Bool,
                    lastRatingAskAt: Date?,
                    now: Date = Date()) -> Bool {
        guard onboardingComplete, sessionsRun >= minSessions, !done, shown.count < maxShowings else { return false }
        if let rating = lastRatingAskAt, now.timeIntervalSince(rating) < ratingClearSec { return false }
        guard let last = shown.max() else { return true }
        return now.timeIntervalSince(last) >= laterGapSec
    }

    // MARK: - What this phone has shown

    static func shownAt(_ defaults: UserDefaults = .standard) -> [Date] {
        (defaults.array(forKey: shownKey) as? [Date]) ?? []
    }

    static func isDone(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: doneKey)
    }

    static func recordShown(now: Date = Date(), _ defaults: UserDefaults = .standard) {
        defaults.set(shownAt(defaults) + [now], forKey: shownKey)
    }

    static func record(_ answer: Answer, _ defaults: UserDefaults = .standard) {
        if answer.isFinal { defaults.set(true, forKey: doneKey) }
    }
}
