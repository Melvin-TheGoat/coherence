import Foundation

/// When to ask for an App Store rating. Pure, so the rule is testable.
///
/// The rules come from the App Review pass of 2026-08-11 and are not
/// negotiable: the prompt is UNCONDITIONAL on how the session went (routing
/// only happy users to Apple's sheet is ratings manipulation and a live
/// rejection reason) and it fires after a completed session. Onboarding
/// also asks once, on "808 was made for people like you" (Aziz, 2026-09-26,
/// reversing the old never-in-onboarding rule); that ask is unconditional
/// too and does not stamp `lastAskedKey`. Apple's own sheet caps itself at three showings per 365 days
/// whatever we ask, so the cooldown here is about not being tiresome, not
/// about the limit.
enum ReviewPrompt {
    /// Enough sessions that the person has an opinion. The first sit is the
    /// onboarding practice; the second is the first real one.
    static let minSessions = 3
    /// Ninety days between asks.
    static let cooldownSec: TimeInterval = 90 * 24 * 3600
    static let lastAskedKey = "reviewPrompt.lastAskedAt"

    static func shouldAsk(sessionCount: Int,
                          onboardingComplete: Bool,
                          lastAskedAt: Date?,
                          now: Date = Date()) -> Bool {
        guard onboardingComplete, sessionCount >= minSessions else { return false }
        if let last = lastAskedAt, now.timeIntervalSince(last) < cooldownSec { return false }
        return true
    }
}
