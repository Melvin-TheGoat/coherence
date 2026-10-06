import SwiftUI
import WidgetKit

// What the widget draws (2026-10-06, `mockups/widget-v2.html`, direction 1):
// the app's valley as its container background, and Otto, the streak and
// his line as its face. Split from OttoWidget.swift so the timeline and the
// picture each read on their own.

// MARK: - Layout

/// Where the app's valley sits in a widget. The approved mock drew the scene
/// at half the sit's scale on a 164pt widget, cut to a window whose bottom
/// leaves a strip of meadow under his cushion (140pt from the top of the
/// window to the bottom of the cushion). Everything here scales with the
/// widget's height, so a 148pt SE widget and a 170pt Pro Max one hold the
/// same picture.
///
/// The small is centred on him. The medium seats him on the left and gives
/// the scene the width of the mock's 500pt meadow, so the flowers stand
/// where Melvin saw them.
struct WidgetValleyLayout {
    let size: CGSize
    let medium: Bool

    /// The mock's widget was 164pt tall.
    var unit: CGFloat { size.height / 164 }

    /// Otto's centre, across the widget.
    var ottoX: CGFloat { medium ? 104 * unit : size.width / 2 }

    /// The whole scene, of which the widget shows a window.
    var scene: CGSize {
        let height = 620 * 0.5 * unit
        guard medium else { return CGSize(width: size.width, height: height) }
        // Wide enough that the window never runs off its right edge.
        return CGSize(width: max(500 * unit, 2 * (size.width - ottoX)), height: height)
    }

    var scale: CGFloat { SitLayout.scale(in: scene) }

    /// The scene's top left corner, in the widget's coordinates.
    var origin: CGPoint {
        CGPoint(x: ottoX - scene.width / 2,
                y: 140 * unit - SitLayout.cushionBottom(in: scene))
    }

    /// The box the scene seats him in, and its centre in the widget.
    var seated: CGFloat { SitLayout.ottoHeight(in: scene) }
    var ottoCentre: CGPoint {
        CGPoint(x: ottoX, y: origin.y + SitLayout.seatedCentreY(in: scene))
    }

    /// The medium's bubble slot: from just right of Otto to the right edge.
    var bubbleWidth: CGFloat { size.width - 14 - (ottoX + 64 * unit) }
}

// MARK: - The hour

/// The hour a widget paints its sky at: the entry's, or in DEBUG the one the
/// app was launched with (`VALLEY_HOUR`, passed through the App Group).
enum OttoWidgetClock {
    static func progress(at date: Date) -> Double {
        DayLight.clockProgress(at: clock(at: date))
    }

    private static func clock(at date: Date) -> Date {
        #if DEBUG
        if let h = OttoWidgetShelf.defaults?.object(forKey: OttoWidgetShelf.debugHourKey) as? Double {
            return Calendar.current.date(bySettingHour: Int(h), minute: Int((h - h.rounded(.down)) * 60),
                                         second: 0, of: date) ?? date
        }
        #endif
        return date
    }
}

// MARK: - The backdrop

/// The widget's container background: the app's valley at the hour, with
/// his cushion and no Otto. A tinted home screen takes this away, and Otto,
/// in the face over it, keeps his colours.
struct OttoWidgetBackdrop: View {
    let date: Date
    let medium: Bool

    var body: some View {
        GeometryReader { g in
            WidgetValley(layout: WidgetValleyLayout(size: g.size, medium: medium),
                         progress: OttoWidgetClock.progress(at: date), time: date)
        }
    }
}

// MARK: - The face

/// Everything over the valley: Otto on his cushion, the streak in the top
/// left, and on the medium his line in Home's bubble.
struct OttoWidgetFace: View {
    let date: Date
    let snapshot: OttoWidgetSnapshot?
    let medium: Bool

    private var progress: Double { OttoWidgetClock.progress(at: date) }
    private var light: DayLight { DayLight.at(progress) }

    /// The day to show, for a member only. Anyone else, and a phone 808 has
    /// not written to yet, gets the way into 808 and no numbers.
    private var day: OttoWidgetSnapshot.Day? {
        guard let snapshot, snapshot.member else { return nil }
        return snapshot.day(at: date)
    }

    /// The still drawing of his stage, 1 to 7. Without a day to show he sits
    /// at Steady, which is how everybody meets him.
    private var stage: Int { day.map { OttoWidgetSnapshot.stage(level: $0.level) } ?? 4 }

    var body: some View {
        GeometryReader { g in
            let layout = WidgetValleyLayout(size: g.size, medium: medium)
            ZStack(alignment: .topLeading) {
                otto(layout)
                top
                    .padding(.top, 12)
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if medium {
                    bubble
                        .frame(width: layout.bubbleWidth)
                        .padding(.top, 16)
                        .padding(.trailing, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Pieces

    /// His still on the cushion, framed the way `OttoAuraFigure` frames the
    /// app's stills and seated where the scene seats him. The two brightest
    /// stages float, as they do on Home.
    private func otto(_ layout: WidgetValleyLayout) -> some View {
        let seated = layout.seated
        let canvas = seated * 0.95 / OttoStillCanvas.bodyShare
        return Image("WidgetOtto\(stage)")
            .resizable()
            .fullColorWhenAccented()
            .scaledToFit()
            .frame(width: canvas * OttoStillCanvas.aspect, height: canvas)
            .offset(y: canvas * (1 - OttoStillCanvas.baseline))
            .offset(y: stage >= 6 ? -seated * 0.05 : 0)
            .frame(width: seated, height: seated, alignment: .bottom)
            .colorMultiply(Color(white: light.light))
            .position(layout.ottoCentre)
    }

    /// The top left corner: the streak for a member with one going, the way
    /// into 808 for anyone else, and nothing on a day with no flame.
    @ViewBuilder private var top: some View {
        if let day {
            if day.streak > 0 {
                HStack(spacing: 3) {
                    Image("WidgetFlame")
                        .resizable()
                        .fullColorWhenAccented()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    onSky(Text("\(day.streak)"), size: 18)
                }
            }
        } else if !medium {
            onSky(Text("Open 808"), size: 15)
        }
    }

    /// Words straight on the sky, in the hour's ink with a soft halo of the
    /// opposite shade, the way the app writes on its valley.
    private func onSky(_ text: Text, size: CGFloat) -> some View {
        text
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(light.ink)
            .lineLimit(1)
            .shadow(color: light.inkIsDark ? Color.white.opacity(0.5) : Color.black.opacity(0.3), radius: 3)
    }

    /// Home's bubble: the tile sand with its lip, dimmed a little after dark
    /// like Home's tiles, its point aimed down and left at his head.
    private var bubble: some View {
        let dim = min(max((progress - 0.32) / (0.65 - 0.32), 0), 1) * 0.06
        let shape = BubbleShape(cornerRadius: 14, tailDepth: BubbleShape.tailDepth)
        return Text(day?.line ?? "Open 808 to meditate with me. I'll be right here.")
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.leading)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .padding(.bottom, BubbleShape.tailDepth)
            .background {
                shape
                    .fill(Palette.sand)
                    .overlay(Color.black.opacity(dim).clipShape(shape))
                    .shadow(color: Palette.lip, radius: 0, y: 2)
            }
    }

    private var accessibilityText: String {
        guard let day else { return "Otto. Open 808 to meditate with him." }
        var text = "Otto's glow, \(day.level) percent."
        if day.streak > 0 { text += " \(day.streak) day streak." }
        if medium { text += " " + day.line }
        return text
    }
}

/// The app's valley, at the widget's window: the sky, the clouds where the
/// app would have them now, the ridges, the meadow and his cushion, all from
/// `ValleyPainting.swift`. Otto himself is drawn in the widget's content,
/// over this, so he keeps his colours on a tinted home screen.
///
/// The small's sun sits on the right: the streak has the top left, and the
/// daytime sun hung exactly there. The medium's sun is off its left edge,
/// as the mock has it.
private struct WidgetValley: View {
    let layout: WidgetValleyLayout
    let progress: Double
    let time: Date

    var body: some View {
        let scene = layout.scene
        let s = layout.scale
        let day = DayLight.at(progress)
        ZStack {
            ValleySky(day: day, hour: progress, size: scene, scale: s, sunMirrored: !layout.medium)
            ValleyClouds(day: day, hour: progress, size: scene, scale: s,
                         time: time.timeIntervalSinceReferenceDate)
            ValleyLand(day: day, size: scene)
            // The ground takes the hour's light as one group, as in the app.
            ZStack {
                Meadow(scale: s)
                    .frame(width: scene.width, height: scene.height)
                Cushion.seated(in: scene, scale: s)
            }
            .frame(width: scene.width, height: scene.height)
            .colorMultiply(Color(white: day.light))
        }
        .frame(width: scene.width, height: scene.height)
        // Placed by centre: the scene is bigger than the widget, and an
        // offset would widen the stack instead of moving the picture.
        .position(x: layout.origin.x + scene.width / 2, y: layout.origin.y + scene.height / 2)
    }
}

/// The bubble and its point as one outline, so the lip under it follows the
/// point too, the way Home's bubble is drawn. The point sits inside the
/// frame, under the body, aimed down and to the left.
private struct BubbleShape: Shape {
    static let tailDepth: CGFloat = 9
    var cornerRadius: CGFloat
    var tailDepth: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailDepth)
        let r = min(cornerRadius, body.height / 2, body.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        // The point: its base along the bottom edge, its tip out below the
        // bottom left corner, toward his head.
        p.addLine(to: CGPoint(x: body.minX + r + 12, y: body.maxY))
        p.addLine(to: CGPoint(x: body.minX + 10, y: rect.maxY))
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Colours

/// The widget is its own bundle and does not carry the app's asset catalog,
/// so its few fixed colours are literals, sampled from the app's own tokens:
/// the tile sand (`BackgroundSecondary`), the tile lip (`Hairline`), and the
/// bubble's ink. The valley's colours come from `DayLight` and
/// `ValleyPainting.swift`, the app's own.
private enum Palette {
    static let sand = Color(hex: 0xF0E9DC)
    static let lip = Color(hex: 0xE2D8C7)
    static let ink = Color(hex: 0x2B2620)
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private extension Image {
    /// Otto keeps his colours when the home screen is tinted (iOS 18): he is
    /// a drawing of a character, not a glyph, and a monochrome sloth reads as
    /// a sad one.
    @ViewBuilder func fullColorWhenAccented() -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}

