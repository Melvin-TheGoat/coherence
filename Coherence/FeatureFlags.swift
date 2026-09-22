import Foundation

/// Features that are built on `mvp` but not ready for the App Store.
///
/// **Friends (1.1) is ON in Release from this branch** (`social-1.1`, Melvin
/// 2026-09-18: "push the social media aspect ASAP, that seems most desirable
/// by users right now"). Otto and camera vision are deliberately NOT in this
/// release: both need privacy-policy work, and waiting for them would hold
/// up the thing people are actually asking for.
///
/// **Flipping this flag is not the whole release.** RELEASE_CHECKLIST.md's
/// "OPEN for 1.1" list is owed in the SAME submission, and most of it is not
/// code: the six PUBLIC record types deployed to CloudKit PRODUCTION (the
/// 1.0 lesson, where a missing Production schema broke every sign-in for two
/// days), the age-rating questionnaire with UGC and Social flipped to Yes,
/// App Privacy labels for user content and photos, both privacy-policy
/// copies, a terms section on user content, and a report path that reaches a
/// person (guideline 1.2 requires one that works).
enum FeatureFlags {
    static let friendsInRelease = true

    static var friends: Bool {
        #if DEBUG
        return true
        #else
        return friendsInRelease
        #endif
    }

    /// **Otto (the premium on-device chat, 2026-09-15) is OFF in Release** until
    /// Melvin and Aziz have read its answers on a phone and the paid tier's
    /// description, the App Privacy answers and the review notes say what it
    /// is. DEBUG builds keep it on. Off means no Otto row anywhere: a locked
    /// row would sell something the build does not contain.
    static let ottoInRelease = false

    static var otto: Bool {
        #if DEBUG
        return true
        #else
        return ottoInRelease
        #endif
    }

    /// **Block (2026-09-22) is OFF in Release** until it has run on a phone:
    /// the simulator cannot show a shield, so nothing about the holding has
    /// been seen working yet. DEBUG builds (the simulator and the side-by-side
    /// beta) keep it on. Off means the Guide tab where Block would be, and no
    /// Block screen in onboarding. The extensions and the Family Controls
    /// entitlement are compiled in either way; Apple approved the entitlement
    /// for all four App IDs on 2026-09-22.
    static let blockInRelease = false

    static var block: Bool {
        #if DEBUG
        return true
        #else
        return blockInRelease
        #endif
    }

    /// Award ids that belong to a switched-off feature.
    static var hiddenAwardIDs: Set<String> {
        friends ? [] : ["friendBrought"]
    }
}
