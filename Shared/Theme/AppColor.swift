import SwiftUI

/// Central color access. RULE: never hardcode a hex value anywhere in the app —
/// every color routes through here, backed by named colors in
/// `Shared/Assets.xcassets` (each with light + dark appearance variants). The
/// catalog compiles into both the iOS and watchOS targets.
enum AppColor {
    static let backgroundPrimary = Color("BackgroundPrimary")
    static let backgroundSecondary = Color("BackgroundSecondary")
    static let accentGold = Color("AccentGold")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
}
