import Foundation
import SwiftData
import WidgetKit

/// Keeps the home screen widget (OttoWidget/) in step with the app: works out
/// the snapshot from what is stored and hands it over through the App Group.
///
/// Called whenever what the widget shows could have moved: the app coming to
/// the front, the root changing between the app and the paywall, and a
/// session landing or being deleted. The widget redraws itself through the
/// day from the projected days in the snapshot, so nothing needs to run in
/// the background.
@MainActor
enum OttoWidgetPublisher {
    static func publish(context: ModelContext, member: Bool) {
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        var snapshot = OttoWidgetFeed.snapshot(
            sits: sessions.map { OttoAura.Sit(date: $0.startedAt, seconds: $0.durationSec) },
            // The windows come from the phone's own Screen Time state and are
            // only ever priced into the level, as on Home.
            notNow: FeatureFlags.block ? BlockController.shared.notNowWindows : [],
            since: OttoAura.glowStart(),
            member: member)
        #if DEBUG
        // OTTO_AURA=<0...100> shows a stage on a simulator with no history,
        // on Home and on the widget alike.
        if let raw = ProcessInfo.processInfo.environment["OTTO_AURA"], let level = Int(raw) {
            for i in snapshot.days.indices { snapshot.days[i].level = min(max(level, 0), 100) }
        }
        // VALLEY_HOUR=<0...24> paints the widget's sky at that hour too. The
        // widget runs in its own process and never sees the app's launch
        // environment, so the hour travels through the App Group.
        let hour = ProcessInfo.processInfo.environment["VALLEY_HOUR"].flatMap(Double.init)
        if OttoWidgetShelf.defaults?.object(forKey: OttoWidgetShelf.debugHourKey) as? Double != hour {
            OttoWidgetShelf.defaults?.set(hour, forKey: OttoWidgetShelf.debugHourKey)
            WidgetCenter.shared.reloadTimelines(ofKind: OttoWidgetShelf.kind)
        }
        #endif
        if OttoWidgetShelf.write(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: OttoWidgetShelf.kind)
        }
    }
}

/// `coherence808://home`, the widget's tap. The URL arrives at the app's one
/// `.onOpenURL`, and Home is a tab inside ContentView, so it travels as a
/// notification. A cold launch opens on Home anyway.
enum WidgetLink {
    static let home = URL(string: "coherence808://home")!
    static let openHome = Notification.Name("808.widget.openHome")

    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard url.scheme == "coherence808", url.host == "home" else { return false }
        NotificationCenter.default.post(name: openHome, object: nil)
        return true
    }
}
