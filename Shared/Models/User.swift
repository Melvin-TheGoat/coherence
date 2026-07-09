import Foundation
import SwiftData

/// The account holder. Until Phase 7 (Sign in with Apple), the app runs with a
/// single local "bootstrap" User whose `appleUserID == ""`; first sign-in adopts
/// that row rather than creating a second User.
///
/// CloudKit-safe: every stored property is optional or defaulted, no `.unique`,
/// no relationships. Uniqueness (one User per appleUserID) is enforced in code.
@Model
final class User {
    var id: UUID = UUID()
    var appleUserID: String = ""
    var email: String?
    var displayName: String?
    var marketingOptIn: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        appleUserID: String = "",
        email: String? = nil,
        displayName: String? = nil,
        marketingOptIn: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.appleUserID = appleUserID
        self.email = email
        self.displayName = displayName
        self.marketingOptIn = marketingOptIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
