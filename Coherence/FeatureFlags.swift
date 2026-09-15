import Foundation

/// Features that are built on `mvp` but not ready for the App Store.
///
/// **Friends (1.1) is OFF in Release builds.** The next App Store build ships
/// the onboarding fixes (no sign-in before the end, resume) while Friends is
/// still missing its CloudKit public schema, moderation, age-rating answers,
/// privacy labels and policy sections (RELEASE_CHECKLIST.md, "OPEN for 1.1").
/// DEBUG builds (808 Dev, the simulator) keep it ON so work continues.
///
/// With it off the app is exactly the pre-Friends app: the tab reads Search
/// with the "Friends are coming" placeholder (matching the live store
/// screenshots), results have no Post to friends, nothing talks to the public
/// database, and the "Brought a friend" award is not on the shelf.
///
/// **To ship 1.1: set `friendsInRelease` to true in the archive that is
/// submitted for it, after walking the 1.1 checklist.**
enum FeatureFlags {
    static let friendsInRelease = false

    static var friends: Bool {
        #if DEBUG
        return true
        #else
        return friendsInRelease
        #endif
    }

    /// Award ids that belong to a switched-off feature.
    static var hiddenAwardIDs: Set<String> {
        friends ? [] : ["friendBrought"]
    }
}
