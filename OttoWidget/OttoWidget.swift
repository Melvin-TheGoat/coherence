import SwiftUI
import WidgetKit

// OTTO ON THE HOME SCREEN (Melvin, 2026-10-05: "add a widget, so you can see
// what otto looks like from your homescreen"). Small and medium; tapping it
// opens Home.
//
// REDRAWN 2026-10-06 as "the app's valley" (`mockups/widget-v2.html`,
// direction 1, approved by Melvin): Otto sits on his cushion in the same
// valley as Home, both ridges, the real meadow and flowers, the haze, lit
// for the hour and darkening with the ground at night. The painting is the
// app's own (`Coherence/Session/ValleyPainting.swift`, compiled into this
// target), never a copy. Only the streak sits on top, always top left; his
// glow is no longer printed, because his drawing already shows his stage.
// The medium is one continuous scene with his line in Home's own speech
// bubble.
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

/// The widget itself: the face over the valley, and the tap into Home. The
/// two halves live in OttoWidgetScene.swift.
struct OttoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OttoEntry

    var body: some View {
        let medium = family == .systemMedium
        OttoWidgetFace(date: entry.date, snapshot: entry.snapshot, medium: medium)
            // The size rides along so the app can count which one was tapped.
            .widgetURL(URL(string: "coherence808://home?size=\(medium ? "medium" : "small")"))
            .containerBackground(for: .widget) {
                OttoWidgetBackdrop(date: entry.date, medium: medium)
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
