import SwiftUI

// The valley's light, in its own file since 2026-10-05 so the home screen
// widget (OttoWidget/) can compile it beside the app: the widget draws the
// same sky at the same hour, and two copies of these stops would drift.

/// The palette at one moment of the sit, blended from four keyframes: the sun
/// up, the sun on the ridge, the first dark, and the afterglow.
///
/// **It ends at dusk rather than back in daylight.** A sunrise would be a
/// brighter screen at the exact moment somebody is most settled, and the
/// quiet afterglow is a better reward than a bright one. It is also the
/// practical reason the sun sets: by the middle of a sit the screen is dark
/// enough to sit with in a room at night.
struct DayLight {
    var sky: [Color]
    var ridge: [Color]
    var field: [Color]
    var sun: Color
    var glow: Color
    var cloud: Color
    var cloudOpacity: Double
    var starOpacity: Double
    /// What the hour does to everything alive, as a multiply.
    var light: Double
    /// The empty ring against this sky. White on a pale morning is no ring at
    /// all, so the track takes ink early and cream late.
    var ringTrack: Color
    var ink: Color
    var inkSoft: Color
    /// Whether `ink` is the dark (daytime) one. Words drawn on the valley
    /// take a pale halo when it is and a dark one when it is not.
    var inkIsDark: Bool

    private struct Stop {
        let t: Double
        let sky: [UInt32]
        let ridge: [UInt32]
        let field: [UInt32]
        let sun: UInt32, glow: UInt32, glowA: Double
        let cloud: UInt32, cloudA: Double
        let stars: Double
        let light: Double
        let track: UInt32, trackA: Double
        let ink: UInt32, inkSoft: UInt32
    }

    private static let stops: [Stop] = [
        .init(t: 0.00,
              sky: [0x8CBBD4, 0xBBD8E4, 0xE3E8DA, 0xEFE0C9],
              ridge: [0xAFC6CE, 0x8FAFB4, 0x6E9078],
              field: [0x7FA87E, 0x9CBC85],
              sun: 0xFFE9B8, glow: 0xFFE9B8, glowA: 0.55,
              cloud: 0xFFFFFF, cloudA: 0.92,
              stars: 0, light: 1.00,
              track: 0x1C3E4E, trackA: 0.17,
              ink: 0x26404E, inkSoft: 0x47697A),
        .init(t: 0.32,
              sky: [0x6E92B4, 0xB69AA6, 0xE4B189, 0xE9BE92],
              ridge: [0x93A0B4, 0x7C8394, 0x5E6B62],
              field: [0x5F7E67, 0x7A9470],
              sun: 0xFFD79A, glow: 0xFFBE82, glowA: 0.60,
              cloud: 0xF4C3B4, cloudA: 0.90,
              stars: 0, light: 0.92,
              track: 0xFFFFFF, trackA: 0.18,
              ink: 0xFFF6EB, inkSoft: 0xF0DCC9),
        .init(t: 0.65,
              sky: [0x26324A, 0x4A4560, 0x7A5560, 0x96685B],
              ridge: [0x3F4A61, 0x333A4A, 0x262C2E],
              field: [0x232E28, 0x2E3730],
              sun: 0xC98A6A, glow: 0x96685B, glowA: 0.22,
              cloud: 0x3E3D5C, cloudA: 0.85,
              stars: 1, light: 0.72,
              track: 0xFFFFFF, trackA: 0.18,
              ink: 0xFFF6EB, inkSoft: 0xC3B2A4),
        .init(t: 1.00,
              sky: [0x141E33, 0x24293F, 0x453447, 0x6B4740],
              ridge: [0x2A3348, 0x212736, 0x171B1C],
              field: [0x171F1C, 0x212823],
              sun: 0x6B4740, glow: 0x6B4740, glowA: 0.0,
              cloud: 0x2A2A44, cloudA: 0.0,
              stars: 1, light: 0.78,
              track: 0xFFFFFF, trackA: 0.18,
              ink: 0xF3E7D8, inkSoft: 0xC3B2A4)
    ]

    /// Where the real clock sits on the sit's 0 (full day) to 1 (night)
    /// scale: full day from 8 to half past 5, sunset colours toward half past
    /// 7, night from half past 9 to 5, and the sunset stops run backwards for
    /// dawn. Fixed hours, not the local sunset: close enough to read as the
    /// right time of day without asking anyone for their location.
    static func clockProgress(at date: Date = Date(), calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        var h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        #if DEBUG
        // VALLEY_HOUR=<0...24> shows the valley at any hour on a simulator.
        if let raw = ProcessInfo.processInfo.environment["VALLEY_HOUR"], let forced = Double(raw) { h = forced }
        #endif
        let points: [(Double, Double)] = [(0, 1), (5, 1), (6.5, 0.32), (8, 0), (17.5, 0),
                                          (19.5, 0.32), (20.5, 0.65), (21.5, 1), (24, 1)]
        for i in 0..<(points.count - 1) where h >= points[i].0 && h <= points[i + 1].0 {
            let (h0, p0) = points[i], (h1, p1) = points[i + 1]
            return p0 + (p1 - p0) * (h - h0) / (h1 - h0)
        }
        return 0
    }

    /// The valley as it looks at this moment, for type drawn on its sky and
    /// for the grass a page continues under it.
    static var now: DayLight { at(clockProgress()) }

    static func at(_ progress: Double) -> DayLight {
        let t = min(max(progress, 0), 1)
        var lo = stops[0], hi = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where t >= stops[i].t && t <= stops[i + 1].t {
            lo = stops[i]; hi = stops[i + 1]
        }
        let span = hi.t - lo.t
        let k = span <= 0 ? 0 : (t - lo.t) / span

        func c(_ a: UInt32, _ b: UInt32, _ alpha: Double = 1) -> Color {
            blend(a, b, k).opacity(alpha)
        }
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }

        return DayLight(
            sky: (0..<4).map { c(lo.sky[$0], hi.sky[$0]) },
            ridge: (0..<3).map { c(lo.ridge[$0], hi.ridge[$0]) },
            field: (0..<2).map { c(lo.field[$0], hi.field[$0]) },
            sun: c(lo.sun, hi.sun),
            glow: c(lo.glow, hi.glow, mix(lo.glowA, hi.glowA)),
            cloud: c(lo.cloud, hi.cloud),
            cloudOpacity: mix(lo.cloudA, hi.cloudA),
            starOpacity: mix(lo.stars, hi.stars),
            light: mix(lo.light, hi.light),
            ringTrack: c(lo.track, hi.track, mix(lo.trackA, hi.trackA)),
            ink: ink(t, soft: false),
            inkSoft: ink(t, soft: true),
            inkIsDark: t < inkTurn
        )
    }

    /// Where words on the valley change from dark to cream (Aziz,
    /// 2026-09-29: "make sure the contrast is good for all the times in the
    /// day"). Blending the two inks across the sunset, as the stops used to,
    /// passed through a mid grey on a mid sky and read at barely 2:1 around
    /// half past seven. So there is no blend: the ink is dark, then cream.
    /// Measured against the sky: at 0.36 dark and cream both hold about 3:1
    /// at the top of the sky, where most words sit, and past it cream wins
    /// there first. Checked on the simulator at 19.2, 19.75, 19.85 and 23h.
    static let inkTurn = 0.36
    private static let dayInk: UInt32 = 0x1F3643, dayInkSoft: UInt32 = 0x3A5767
    private static let duskInk: UInt32 = 0xFFF6EB, duskInkSoft: UInt32 = 0xF0DCC9
    private static let nightInk: UInt32 = 0xF3E7D8, nightInkSoft: UInt32 = 0xD2C3B6

    private static func ink(_ t: Double, soft: Bool) -> Color {
        let dark = soft ? dayInkSoft : dayInk
        let dusk = soft ? duskInkSoft : duskInk
        let night = soft ? nightInkSoft : nightInk
        if t < inkTurn { return blend(dark, dark, 0) }
        return blend(dusk, night, (t - inkTurn) / (1 - inkTurn))
    }

    private static func blend(_ a: UInt32, _ b: UInt32, _ k: Double) -> Color {
        func part(_ v: UInt32, _ shift: UInt32) -> Double {
            Double((v >> shift) & 0xFF) / 255
        }
        return Color(red: part(a, 16) + (part(b, 16) - part(a, 16)) * k,
                     green: part(a, 8) + (part(b, 8) - part(a, 8)) * k,
                     blue: part(a, 0) + (part(b, 0) - part(a, 0)) * k)
    }

    /// Fixed, not random: a sky that reshuffles its stars every redraw is a
    /// sky nobody can settle under.
    static let stars: [(x: Double, y: Double, alpha: Double)] = [
        (0.35, 0.39, 0.35), (0.52, 0.35, 0.90), (0.79, 0.09, 0.90), (0.06, 0.35, 0.60),
        (0.75, 0.19, 0.35), (0.65, 0.39, 0.90), (0.65, 0.30, 0.90), (0.24, 0.19, 0.90),
        (0.24, 0.38, 0.60), (0.06, 0.09, 0.35), (0.80, 0.07, 0.60), (0.08, 0.22, 0.60),
        (0.81, 0.29, 0.90), (0.59, 0.30, 0.90), (0.78, 0.33, 0.35), (0.51, 0.11, 0.35),
        (0.22, 0.36, 0.35), (0.38, 0.32, 0.90), (0.43, 0.31, 0.90), (0.54, 0.27, 0.90),
        (0.79, 0.31, 0.90), (0.34, 0.26, 0.90)
    ]
}
