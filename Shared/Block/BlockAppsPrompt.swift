import Foundation

/// When Otto asks someone to pick an app for him to hold (2026-10-13, Melvin
/// and Aziz: "we want it mandatory that you block at least one app").
///
/// New members are asked during onboarding, where the pick is required once
/// Screen Time access is allowed. Everyone who joined before that, or who
/// declined Screen Time then, never sees onboarding again, and they are the
/// people not meditating. So Home asks them ONCE: when they have no apps held
/// and Block is open to them. Asked in onboarding counts as asked.
enum BlockAppsPrompt {
    static let askedKey = "block.appsPromptAsked.v1"

    static func shouldAsk(blockers: [Blocker], asked: Bool, allowed: Bool) -> Bool {
        allowed && !asked && !blockers.contains { $0.hasApps }
    }

    static func wasAsked(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: askedKey)
    }

    static func markAsked(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: askedKey)
    }
}
