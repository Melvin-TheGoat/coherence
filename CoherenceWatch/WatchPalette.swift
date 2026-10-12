import SwiftUI

/// Explicit colors for the Watch UI.
///
/// **Why not the shared `AppColor` assets:** those colorsets carry a light and
/// a dark variant, and watchOS resolves the LIGHT one — `TextSecondary`'s light
/// value is 0.42 grey, which on the Watch's permanently black screen reads as
/// unreadable near-black (observed on-device: every subtitle vanished, and the
/// teal orb looked like a bare outline).
///
/// The Watch has exactly one appearance, so it gets one set of literal values.
/// Since 2026-10-12 the Watch stands in the app's valley (`DayLight` and
/// `ValleyPainting.swift`, compiled in), so most of its colours are the
/// iPhone's: sand pills, the gold Begin, the sage arc. Words on the sky take
/// the hour's ink from `DayLight`, never a colour from here.
enum WatchPalette {
    static let ink       = Color(red: 0.961, green: 0.953, blue: 0.925)   // TextPrimary (dark)
    static let inkMuted  = Color(red: 0.604, green: 0.604, blue: 0.576)   // TextSecondary (dark)
    static let gold      = Color(red: 0.831, green: 0.686, blue: 0.216)   // AccentGold (dark)
    static let calm      = Color(red: 0.451, green: 0.659, blue: 0.631)   // CalmAccent (dark)
    static let warn      = Color(red: 0.780, green: 0.480, blue: 0.430)   // End / wrong-direction
    static let surface   = Color(white: 0.10)                             // rows, pills
    static let onGold    = Color(red: 0.090, green: 0.070, blue: 0.030)   // ink on a gold fill

    // The iPhone's, for the valley screens.
    /// A pill or a card: the tile sand (`BackgroundSecondary`).
    static let sand      = Color(hex: 0xF0E9DC)
    /// The lip under a sand pill (`Hairline`).
    static let sandLip   = Color(hex: 0xE2D8C7)
    /// Words on sand.
    static let sandInk   = Color(hex: 0x2B2620)
    static let sandInkSoft = Color(hex: 0x6F5D4F)
    /// The lifted gold button (`AccentGold`, `PrimaryButtonStyle`).
    static let begin     = Color(hex: 0xF0C47B)
    static let beginLip  = Color(hex: 0xC9964A)
    static let beginInk  = Color(hex: 0x3A2A12)
    /// The chosen sound's outline and tick (`AccentGoldText`).
    static let chosen    = Color(hex: 0x81591A)
    /// The sit ring's arc (`CalmAccentFill`).
    static let arc       = Color(hex: 0x93C9BE)
    /// The length tape's needle.
    static let needle    = Color(hex: 0xD9902E)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
