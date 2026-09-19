import Foundation
import SwiftData

/// Per-user settings. FK to User is a plain `userID: UUID?` (not a `@Relationship`).
/// `defaultDurationSec == nil` means the remembered pick is "open-ended".
@Model
final class Preferences {
    var id: UUID = UUID()
    var userID: UUID?
    var onboardingComplete: Bool = false
    var defaultDurationSec: Int?          // nil = open-ended
    var remindersEnabled: Bool = false
    var reminderTime: Date?
    /// Light by default (Aziz, 2026-09-19). It was dark from 2026-08-08, when
    /// every screen had been designed dark-first. The palette is now taken out
    /// of Otto's artwork, which is cream, and a warm character on a near-black
    /// ground is the one arrangement that makes him look pasted on. Dark and
    /// system stay available in Settings and both get the same warm treatment;
    /// existing users keep whatever they had stored, so this only changes the
    /// first impression, which is the thing it is meant to change.
    var theme: String = "light"
    /// The same default, readable before any row exists. `RootView` applies
    /// it to onboarding, which runs before the first Preferences row is
    /// written. Keep the two in lockstep.
    static let defaultTheme: Theme = .light
    var hapticsEnabled: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: Invite reward (COMMUNITY.md, added 2026-09-14; all defaulted so
    // the migration is lightweight and CloudKit-safe)

    /// Sessions of full evidence still owed: ten per friend who was invited,
    /// accepted, and sat once. Capped at `InviteReward.cap` outstanding.
    var evidenceGrantRemaining: Int = 0
    /// When the first grant landed. Only sessions started after it consume
    /// one: "your NEXT three sessions", not three old ones.
    var evidenceGrantSince: Date?
    /// Profile record names already paid out, so a friend rewards once.
    var rewardedFriends: [String] = []
    /// Sessions a grant covered. Read forever, so a covered session keeps its
    /// evidence after the grant runs out.
    var grantedSessionIDs: [String] = []

    /// Computed accessor over the String-backed `theme`.
    var themeValue: Theme {
        get { Theme(rawValue: theme) ?? .system }
        set { theme = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        onboardingComplete: Bool = false,
        defaultDurationSec: Int? = nil,
        remindersEnabled: Bool = false,
        reminderTime: Date? = nil,
        // THREE places carry this default and all three must agree: the stored
        // property, `defaultTheme`, and this initialiser. The initialiser is
        // the one that actually decides, because that is how a row gets made,
        // and it silently said "system" while the other two said "dark" for
        // six weeks. On a light-mode phone that was invisible; on a dark one it
        // looked correct for the wrong reason.
        theme: String = "light",
        hapticsEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.onboardingComplete = onboardingComplete
        self.defaultDurationSec = defaultDurationSec
        self.remindersEnabled = remindersEnabled
        self.reminderTime = reminderTime
        self.theme = theme
        self.hapticsEnabled = hapticsEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
