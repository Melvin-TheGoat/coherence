import SwiftUI
import WidgetKit

// OTTO ON THE HOME SCREEN (Melvin, 2026-10-05: "add a widget, so you can see
// what otto looks like from your homescreen"). Built to
// `mockups/widget-v1.html`: small and medium, Otto in the valley at the real
// hour, his glow and the streak, and on the medium the line he would say on
// Home right now. Tapping it opens Home.
//
// The widget works out nothing: the app writes `OttoWidgetSnapshot` into the
// App Group whenever the glow could have moved, including the next few days
// as they will stand if nobody meditates, and the widget picks the day and
// paints the sky for the hour. Otto is the still drawing of his stage (a
// widget cannot run the Rive rig), the same seven the app falls back to.

@main
struct OttoWidgetBundle: WidgetBundle {
    var body: some Widget { OttoWidget() }
}

struct OttoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: OttoWidgetShelf.kind, provider: OttoProvider()) { entry in
            OttoWidgetView(entry: entry)
        }
        .configurationDisplayName("Otto")
        .description("See how Otto is doing, with his glow and your streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct OttoEntry: TimelineEntry {
    let date: Date
    let snapshot: OttoWidgetSnapshot?
}

struct OttoProvider: TimelineProvider {
    func placeholder(in context: Context) -> OttoEntry {
        OttoEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (OttoEntry) -> Void) {
        let saved = OttoWidgetShelf.read()
        // The gallery shows your own Otto when there is one to show, and a
        // sample otherwise, so the gallery never shows an empty widget.
        let shown = context.isPreview && saved?.member != true ? .sample() : saved
        completion(OttoEntry(date: Date(), snapshot: shown))
    }

    /// Every half hour for a day: the sky follows the hour (the sunset runs
    /// over two hours, so hourly steps would show), and the day the snapshot
    /// projected takes over at midnight. The app reloads the timeline itself
    /// whenever the glow moves, so this only has to carry the quiet hours.
    func getTimeline(in context: Context, completion: @escaping (Timeline<OttoEntry>) -> Void) {
        let snapshot = OttoWidgetShelf.read()
        let now = Date()
        let cal = Calendar.current
        var dates = [now]
        // The first half hour mark after now (:30 or the next :00), then
        // every half hour, which lands an entry on midnight.
        let hour = cal.dateInterval(of: .hour, for: now)?.start ?? now
        var mark = hour.addingTimeInterval(now.timeIntervalSince(hour) < 30 * 60 ? 30 * 60 : 60 * 60)
        while dates.count < 49 {
            dates.append(mark)
            mark = mark.addingTimeInterval(30 * 60)
        }
        completion(Timeline(entries: dates.map { OttoEntry(date: $0, snapshot: snapshot) },
                            policy: .atEnd))
    }
}

extension OttoWidgetSnapshot {
    /// What the gallery shows before 808 has written anything: Otto at
    /// Steady on a five-day streak, the mockup's first widget.
    static func sample(now: Date = Date()) -> OttoWidgetSnapshot {
        OttoWidgetSnapshot(member: true,
                           days: [Day(start: Calendar.current.startOfDay(for: now), level: 52, streak: 5,
                                      line: "Whenever you're ready. One session is all today asks.")],
                           written: now)
    }
}

// MARK: - The widget

struct OttoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OttoEntry

    private var progress: Double { DayLight.clockProgress(at: clock) }

    /// The hour the sky is painted at: the entry's, or in DEBUG the one the
    /// app was launched with (`VALLEY_HOUR`, passed through the App Group).
    private var clock: Date {
        #if DEBUG
        if let h = OttoWidgetShelf.defaults?.object(forKey: OttoWidgetShelf.debugHourKey) as? Double {
            return Calendar.current.date(bySettingHour: Int(h), minute: Int((h - h.rounded(.down)) * 60),
                                         second: 0, of: entry.date) ?? entry.date
        }
        #endif
        return entry.date
    }
    private var light: DayLight { DayLight.at(progress) }

    /// The day to show, for a member only. Anyone else, and a phone 808 has
    /// not written to yet, gets the way into 808 and no numbers.
    private var day: OttoWidgetSnapshot.Day? {
        guard let snapshot = entry.snapshot, snapshot.member else { return nil }
        return snapshot.day(at: entry.date)
    }

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        .widgetURL(URL(string: "coherence808://home"))
        .containerBackground(for: .widget) {
            if family == .systemMedium {
                HStack(spacing: 0) {
                    ValleyBackdrop(light: light, progress: progress)
                    Panel.fill(progress: progress)
                }
            } else {
                ValleyBackdrop(light: light, progress: progress)
            }
        }
    }

    // MARK: Small

    private var small: some View {
        ZStack {
            otto(height: 104)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 30)
            if let day, day.streak > 0 {
                streakBadge(day.streak)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 11)
                    .padding(.leading, 12)
            }
            pill
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var pill: some View {
        Group {
            if let day {
                (Text("Glow ") + Text("\(day.level)%").foregroundColor(Palette.glowText))
            } else {
                Text("Open 808")
            }
        }
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .background(Palette.sand.opacity(0.93), in: Capsule())
        .shadow(color: Palette.lip.opacity(0.18), radius: 0, y: 2)
    }

    private func streakBadge(_ streak: Int) -> some View {
        HStack(spacing: 3) {
            Image("WidgetFlame")
                .resizable()
                .fullColorWhenAccented()
                .scaledToFit()
                .frame(width: 20, height: 20)
            Text("\(streak)")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(light.ink)
                .shadow(color: (light.inkIsDark ? Color.white.opacity(0.45) : Color.black.opacity(0.25)), radius: 3)
        }
    }

    // MARK: Medium

    private var medium: some View {
        HStack(spacing: 0) {
            ZStack {
                otto(height: 128)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity)
            Panel(day: day)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Pieces

    /// The still drawing of his stage. Without a day to show he sits at
    /// Steady, which is how everybody meets him.
    private func otto(height: CGFloat) -> some View {
        let stage = day.map { OttoWidgetSnapshot.stage(level: $0.level) } ?? 4
        return Image("WidgetOtto\(stage)")
            .resizable()
            .fullColorWhenAccented()
            .scaledToFit()
            .frame(height: height)
    }

    private var accessibilityText: String {
        guard let day else { return "Otto. Open 808 to meditate with him." }
        var text = "Otto's glow, \(day.level) percent."
        if day.streak > 0 { text += " \(day.streak) day streak." }
        if family == .systemMedium { text += " " + day.line }
        return text
    }
}

/// The medium widget's right half: Otto's words on the app's sand.
private struct Panel: View {
    let day: OttoWidgetSnapshot.Day?

    /// Sand, dimmed a little after dark, like Home's tiles (`tileDim`).
    static func fill(progress: Double) -> some View {
        let dim = min(max((progress - 0.32) / (0.65 - 0.32), 0), 1) * 0.06
        return Palette.sand.overlay(Color.black.opacity(dim))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let day {
                Text("OTTO'S GLOW")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.2)
                    .foregroundStyle(Palette.soft)
                Text("\(day.level)%")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(Palette.ink)
                GlowBar(level: day.level)
                    .padding(.top, 6)
                    .padding(.bottom, 9)
                Text(day.line)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(1)
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                if day.streak > 0 {
                    HStack(spacing: 4) {
                        Image("WidgetFlame")
                            .resizable()
                            .fullColorWhenAccented()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                        Text("\(day.streak)-day streak")
                            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.soft)
                    }
                }
            } else {
                Text("Meditate with Otto")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text("Open 808 to start.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.soft)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .padding(.leading, 16)
        .padding(.trailing, 14)
    }
}

private struct GlowBar: View {
    let level: Int

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [Palette.glowLight, Palette.glow],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(7, g.size.width * CGFloat(min(max(level, 0), 100)) / 100))
            }
        }
        .frame(height: 7)
    }
}

// MARK: - The valley

/// The valley behind Otto, drawn from the app's own `DayLight` at the real
/// hour: the sky, a sun that sets and a moon after dark, the ridge, the
/// meadow and a few flowers. A simpler painting than the app's scene,
/// because a widget is a picture a few centimetres across, but the same
/// colours at the same hour.
private struct ValleyBackdrop: View {
    let light: DayLight
    let progress: Double

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: [.init(color: light.sky[0], location: 0),
                                       .init(color: light.sky[1], location: 0.38),
                                       .init(color: light.sky[2], location: 0.62),
                                       .init(color: light.sky[3], location: 0.74)],
                               startPoint: .top, endPoint: .bottom)
                if light.starOpacity > 0.01 {
                    Canvas { ctx, size in
                        for star in DayLight.stars {
                            let r = star.alpha > 0.8 ? 0.65 : 0.5
                            let rect = CGRect(x: star.x * size.width - r, y: star.y * size.height - r,
                                              width: r * 2, height: r * 2)
                            ctx.fill(Path(ellipseIn: rect),
                                     with: .color(.white.opacity(star.alpha * light.starOpacity * 0.85)))
                        }
                    }
                }
                sunAndMoon(w: w, h: h)
                // Placed by centre, so the ridge's overhang past both sides
                // never widens the stack and shifts everything else.
                Ridge()
                    .fill(LinearGradient(colors: [light.ridge[0], light.ridge[1]],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 1.2, height: h * 0.40)
                    .position(x: w / 2, y: h * (1 - 0.22 - 0.20))
                Rectangle()
                    .fill(LinearGradient(colors: [light.field[1], light.field[0]],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: h * 0.30)
                    .position(x: w / 2, y: h * 0.85)
                Canvas { ctx, size in
                    for f in Flowers.all {
                        let rect = CGRect(x: f.x * size.width - f.r, y: f.y * size.height - f.r,
                                          width: f.r * 2, height: f.r * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(f.color.opacity(0.35 + 0.65 * light.light)))
                    }
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }

    /// The sun sinks to the ridge through the evening; after dark a moon
    /// rises in its place, high and to the right.
    @ViewBuilder private func sunAndMoon(w: CGFloat, h: CGFloat) -> some View {
        let unit = min(w, h)
        let sunSize = unit * 0.2
        let sink = min(progress / 0.5, 1)
        let sunY = h * (0.18 + 0.44 * sink)
        let sunFade = 1 - min(max((progress - 0.4) / 0.15, 0), 1)
        if sunFade > 0 {
            Circle()
                .fill(light.sun)
                .frame(width: sunSize, height: sunSize)
                .shadow(color: light.glow, radius: unit * 0.12)
                .position(x: w * 0.78, y: sunY)
                .opacity(sunFade)
        }
        let moon = min(max((progress - 0.55) / 0.12, 0), 1)
        if moon > 0 {
            Circle()
                .fill(Palette.moon)
                .frame(width: unit * 0.13, height: unit * 0.13)
                .shadow(color: Palette.moon.opacity(0.35), radius: unit * 0.06)
                .position(x: w * 0.8, y: h * 0.2)
                .opacity(moon)
        }
    }
}

/// The far ridge, the mockup's outline.
private struct Ridge: Shape {
    func path(in r: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(0, 0.60), (0.14, 0.35), (0.26, 0.52), (0.40, 0.22), (0.55, 0.48),
                                         (0.68, 0.30), (0.82, 0.50), (1, 0.28), (1, 1), (0, 1)]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let point = CGPoint(x: r.minX + pt.0 * r.width, y: r.minY + pt.1 * r.height)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

/// A handful of flowers in the meadow, fixed so the widget never reshuffles.
private enum Flowers {
    struct Flower { let x: CGFloat, y: CGFloat, r: CGFloat, color: Color }
    static let all: [Flower] = [
        .init(x: 0.10, y: 0.83, r: 1.8, color: Palette.pink),
        .init(x: 0.24, y: 0.90, r: 1.8, color: Palette.cream),
        .init(x: 0.40, y: 0.80, r: 1.4, color: .white),
        .init(x: 0.64, y: 0.92, r: 1.5, color: Palette.cream),
        .init(x: 0.78, y: 0.85, r: 1.8, color: Palette.pink),
        .init(x: 0.90, y: 0.93, r: 1.8, color: .white),
    ]
}

// MARK: - Colours

/// The widget is its own bundle and does not carry the app's asset catalog,
/// so its few fixed colours are literals, sampled from the app's own tokens:
/// the tile sand (`BackgroundSecondary`), the aura's gold (`AuraGlow`), and
/// the mockup's inks.
private enum Palette {
    static let sand = Color(hex: 0xF0E9DC)
    static let ink = Color(hex: 0x2B2620)
    static let soft = Color(hex: 0x6E6458)
    static let lip = Color(hex: 0x786450)
    static let glow = Color(hex: 0xFFBD4D)
    static let glowLight = Color(hex: 0xFFD27A)
    static let glowText = Color(hex: 0xB0741A)
    static let moon = Color(hex: 0xF3E6C8)
    static let pink = Color(hex: 0xF6D9E3)
    static let cream = Color(hex: 0xFFF3C4)
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

#Preview("Small", as: .systemSmall) {
    OttoWidget()
} timeline: {
    OttoEntry(date: Date(), snapshot: .sample())
}

#Preview("Medium", as: .systemMedium) {
    OttoWidget()
} timeline: {
    OttoEntry(date: Date(), snapshot: .sample())
}
