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
    /// Dark by default (Aziz, 2026-08-08): every screen was designed
    /// dark-first, so first impressions match the design intent. Light and
    /// system stay available in Settings; existing users keep whatever they
    /// had stored.
    var theme: String = "dark"
    var hapticsEnabled: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: Invite reward (COMMUNITY.md, added 2026-09-14; all defaulted so
    // the migration is lightweight and CloudKit-safe)

    /// Sessions of full evidence still owed: ten per friend who was invited,
    /// accepted, and sat once. Capped at `InviteReward.cap` outstanding.
    var evidenceGrantRemaining: Int = 0
    /// When the first grant landed. Only sessions started after it consume
    /// one: "your NEXT ten sessions", not ten old ones.
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
        theme: String = "system",
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
