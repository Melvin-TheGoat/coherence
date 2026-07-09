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
    var theme: String = "system"
    var hapticsEnabled: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

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
