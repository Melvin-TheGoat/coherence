import SwiftUI

/// Central color access. RULE: never hardcode a hex value anywhere in the app.
/// Every color routes through here, backed by named colors in
/// `Shared/Assets.xcassets` (each with light + dark appearance variants). The
/// catalog compiles into both the iOS and watchOS targets.
///
/// **808 has ONE appearance** (2026-09-19, Aziz: "get rid of the dark mode").
/// Every colorset carries the same value in both light and dark, and
/// `RootView` pins the scheme to light, so the two can never drift. The
/// reason is Otto: the palette is sampled out of his artwork and the artwork
/// is cream, so a dark build would need a second drawing of him and a second
/// set of every tint. A product with one character gets one room.
///
/// **The fills are pastel; the text tokens are not.** Aziz asked for softer
/// (2026-09-19) and softer is right for anything that is a shape: the score
/// fill, the sage curves, the blush, the empty days. It is wrong for anything
/// that is a word. Each of `textSecondary`, `accentGoldText`, `calmAccent`
/// and `streakBlushText` was pushed back down until it cleared 4.5:1 on both
/// the paper and a card, because a pastel label is an illegible label and
/// legibility is not a style choice. The first pass of this palette put four
/// of them between 4.0 and 4.46 and every one of them looked fine. When the
/// cards went from white to sand (2026-09-26) all four went about a sixth
/// darker, so they clear 4.5 on the sand AND on Home's night-dimmed sand.
///
/// **Every value here is sampled out of Otto** (2026-09-19, Aziz: the app is
/// hard to look at, make it friendly). The paper is the cream his artwork sits
/// on, the ink is his nose and smile, the streak is his cheeks. A mascot only
/// looks native if the room was painted from him rather than around him, and
/// the practical version of that rule is: nothing in this app gets a colour he
/// does not already have. The one import is the sage, because he carries no
/// green and the body's own signals have to be unmistakably not-your-score.
///
/// The three meanings are unchanged from the dark palette and are what let a
/// screen be read in one vertical sweep:
/// **amber = a measured score**, **sage = your body's signals**,
/// **blush = the streak**. Exactly one of them is loud per section.
enum AppColor {
    static let backgroundPrimary = Color("BackgroundPrimary")
    /// Every tile and card: zen-garden sand, #F0E9DC (Melvin, 2026-09-26:
    /// "an off-white, closer to zen garden sand"). It was pure white, which
    /// glared on the valley. Draw tiles through `TileFill` so they dim with
    /// Home's night sky; never fill a tile with `.white`.
    static let backgroundSecondary = Color("BackgroundSecondary")
    /// Gold as a FILL: buttons, rings, tinted discs. Light mode runs it
    /// LIGHTER than dark mode, which is the opposite of the usual instinct and
    /// is correct: the label on a gold plate is near-black, so a lighter plate
    /// gains contrast (10.04 against 8.07 before).
    static let accentGold = Color("AccentGold")

    /// Gold as TEXT on a background: score numbers, the streak digit, "See all".
    /// A separate token because no single gold can be both a bright plate and a
    /// readable number. The fill at 10.04 on its label reads only 1.78 as text
    /// on the light background; this one reads 4.51. In DARK mode both resolve
    /// to the same gold, so nothing about that theme changes.
    static let accentGoldText = Color("AccentGoldText")

    /// The side of a primary button: the darker amber it stands on, so pressing
    /// it closes a real gap. See `PrimaryButtonStyle`.
    static let accentGoldShade = Color("AccentGoldShade")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    /// Sage as TEXT: the "Heart" / "Stillness" / "Breathing" labels. Split from
    /// the fill for the same reason gold was: no single sage is both a legible
    /// label on cream and a curve you can see across a chart. This one reads
    /// 4.6:1 on the paper; the fill reads 2.6 and would be a failing label.
    static let calmAccent = Color("CalmAccent")

    /// Sage as a FILL: every curve drawn off the body, and the doorway band.
    static let calmAccentFill = Color("CalmAccentFill")

    /// Blush as a FILL: the streak card, its tint, the practised-day rest chip.
    /// Lifted off Otto's cheeks. Its whole job is to take the streak OFF gold,
    /// which is what made the old home screen read busy: gold meant both "you
    /// scored this" and "you showed up", so the one-gold-thing-per-section rule
    /// was impossible to keep. Two meanings, two colours, and the rule holds by
    /// itself.
    static let streakBlush = Color("StreakBlush")

    /// Blush as TEXT: the streak digit. The fill is far too pale to read at any
    /// size on cream (1.5:1); this is 4.5.
    static let streakBlushText = Color("StreakBlushText")
    /// The label on top of the amber accent. It is Otto's own ink, NOT white:
    /// white on the amber is 2.1:1, which fails even the large-bold bar, and a
    /// friendly palette is not a licence to ship an unreadable button. Ink on
    /// amber is 6.7:1 and reads warmer anyway.
    static let textOnAccent = Color("TextOnAccent")

    /// The warm line under a card. Replaces the old hairline border: on cream a
    /// stroke reads as a drawn box, a 2pt bottom edge reads as an object.
    static let hairline = Color("Hairline")

    /// The top of the sky Otto sits under on Home. It fades into the paper, so
    /// the top of the screen is a PLACE rather than another panel. That is the
    /// whole difference between a mascot who is in the app and one who is on
    /// it, and it is the pattern under Finch, which is the only app in this
    /// category to have made a mascot work at scale.
    static let sky = Color("Sky")

    /// An empty slot: the week strip's unsat days, and any place something is
    /// drawn before it has happened. Deep enough to be a shape on a WHITE card
    /// rather than only on the paper, which is the mistake it was born from.
    static let trace = Color("Trace")

    /// Otto's aura: the warm light around him at In flow and Enlightened
    /// (`OttoAura`). It is LIGHT, not a score, so it is drawn as a glow and as
    /// orbits of light, never as a closed ring with a number in it; the gold
    /// ring still means a measured score and nothing else.
    static let auraGlow = Color("AuraGlow")
    /// The orbits and sparks inside the glow, a shade deeper so they read
    /// against it on the cream.
    static let auraRing = Color("AuraRing")

    /// What is CHOSEN on a settings screen that stands in the valley: the
    /// segment that is on, the lit day, the picked limit (Aziz, 2026-09-22,
    /// from Brainrot's blocker editor). It is the valley's midday sky
    /// (`DayLight.at(0)`) deepened until bold white text reads on it.
    ///
    /// **Why not gold here.** The old editor lit its choices with a gold wash
    /// on cream, which read as the pastel brown Aziz asked to lose, and on a
    /// screen of choices it spent gold on every one. Blue is for choosing,
    /// and the one gold object is the button that commits the choice.
    static let skyDeep = Color("SkyDeep")
    /// The lip under a lit `skyDeep` segment, so it reads as pressed-in the
    /// way the gold primary button does.
    static let skyDeepEdge = Color("SkyDeepEdge")
    /// The pale sky behind a blocker's symbol.
    static let skyWash = Color("SkyWash")
    /// An option that is NOT chosen, on a white field in the valley: a muted
    /// green from the meadow, so a screen of unpicked choices does not read
    /// as the brown-on-cream Aziz asked to lose.
    static let meadowInk = Color("MeadowInk")
}
