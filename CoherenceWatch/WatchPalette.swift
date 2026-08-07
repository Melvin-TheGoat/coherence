import SwiftUI

/// Explicit colors for the Watch UI.
///
/// **Why not the shared `AppColor` assets:** those colorsets carry a light and
/// a dark variant, and watchOS resolves the LIGHT one — `TextSecondary`'s light
/// value is 0.42 grey, which on the Watch's permanently black screen reads as
/// unreadable near-black (observed on-device: every subtitle vanished, and the
/// teal orb looked like a bare outline).
///
/// The Watch has exactly one appearance, so it gets one set of literal values,
/// matched to the dark variants the design was drawn against. No resolution,
/// nothing to get wrong.
enum WatchPalette {
    static let ink       = Color(red: 0.961, green: 0.953, blue: 0.925)   // TextPrimary (dark)
    static let inkMuted  = Color(red: 0.604, green: 0.604, blue: 0.576)   // TextSecondary (dark)
    static let gold      = Color(red: 0.831, green: 0.686, blue: 0.216)   // AccentGold (dark)
    static let calm      = Color(red: 0.451, green: 0.659, blue: 0.631)   // CalmAccent (dark)
    static let warn      = Color(red: 0.780, green: 0.480, blue: 0.430)   // End / wrong-direction
    static let surface   = Color(white: 0.10)                             // rows, pills
    static let onGold    = Color(red: 0.090, green: 0.070, blue: 0.030)   // ink on a gold fill
}
