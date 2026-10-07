import SwiftUI
import WidgetKit

/// Whether an 808 widget is on the home screen, and which sizes: asked of
/// WidgetCenter each time 808 comes back (1.2, Melvin, 2026-10-07: "I'm
/// curious"). It feeds two things and nothing else: the `widget_added` /
/// `widget_removed` events with the `has_widget` flag, and Otto's line on
/// Home pointing at the widget, which he stops saying once one is there.
@MainActor
final class WidgetPresence: ObservableObject {
    static let shared = WidgetPresence()

    /// The sizes on the home screen; nil until WidgetCenter has answered
    /// once, so Otto never suggests a widget that might already be there.
    @Published private(set) var sizes: Set<String>?

    /// What was there last time, so a change is reported once.
    private static let key = "widget.sizes.v1"

    func refresh() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case .success(let configs) = result else { return }
            let now = Set(configs.filter { $0.kind == OttoWidgetShelf.kind }.map { Self.name($0.family) })
            Task { @MainActor in self.update(now) }
        }
    }

    private func update(_ now: Set<String>) {
        let stored = UserDefaults.standard.stringArray(forKey: Self.key).map(Set.init)
        // The first answer on a phone counts what is already there as added,
        // so widgets put up before this build are not invisible.
        for size in now.subtracting(stored ?? []).sorted() {
            Analytics.track(.widgetAdded(size: size))
        }
        for size in (stored ?? []).subtracting(now).sorted() {
            Analytics.track(.widgetRemoved(size: size))
        }
        UserDefaults.standard.set(now.sorted(), forKey: Self.key)
        Analytics.setHasWidget(!now.isEmpty)
        sizes = now
    }

    static func name(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: return "small"
        case .systemMedium: return "medium"
        default: return "other"
        }
    }
}
