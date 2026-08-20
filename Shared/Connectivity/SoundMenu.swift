import Foundation

/// The sound catalog as the Watch sees it: names and ids only, no audio.
///
/// Every bed, tone, and track lives in the iOS bundle and plays on the phone
/// (the Watch ships no audio — the beds alone are tens of MB). So the Watch
/// picker needs a lightweight menu whose ids the phone's real catalogs
/// (`FrequencyCatalog` / `NatureCatalog` / `GuidedCatalog`) resolve. This file
/// is that menu, compiled into both targets; `SoundMenuTests` locks it against
/// the phone catalogs so the two can't drift apart silently.
///
/// Order matches the shipped sound sheet: Guided first (the only original
/// content we own), Nature by familiarity, Brainwave deepest-first, Tones
/// low-to-high. Silence is the default and lives outside the groups.
public enum SoundMenu {

    public struct Entry: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let detail: String?

        public init(id: String, title: String, detail: String? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
        }
    }

    public struct Group: Identifiable, Equatable {
        public let name: String
        public let entries: [Entry]
        public var id: String { name }

        public init(name: String, entries: [Entry]) {
            self.name = name
            self.entries = entries
        }
    }

    public static let groups: [Group] = [
        Group(name: "Guided", entries: [
            Entry(id: "guided.identity", title: "Dream Life", detail: "25 min"),
        ]),
        Group(name: "Nature", entries: [
            Entry(id: "rain", title: "Rain"),
            Entry(id: "ocean", title: "Ocean"),
            Entry(id: "forest", title: "Forest"),
            Entry(id: "campfire", title: "Campfire"),
        ]),
        Group(name: "Brainwave", entries: [
            Entry(id: "delta", title: "Deep Rest", detail: "2.5 Hz"),
            Entry(id: "theta", title: "Deep Meditation", detail: "6 Hz"),
            Entry(id: "alpha", title: "Calm", detail: "8 Hz"),
        ]),
        Group(name: "Tones", entries: [
            Entry(id: "harmony", title: "Harmony", detail: "432 Hz"),
            Entry(id: "manifest", title: "Manifest", detail: "528 Hz"),
            Entry(id: "visualize", title: "Visualize", detail: "852 Hz"),
            Entry(id: "awaken", title: "Awaken", detail: "963 Hz"),
        ]),
    ]

    public static var allEntries: [Entry] { groups.flatMap(\.entries) }

    /// Display title for a selection; nil/empty means Silence.
    public static func title(for id: String?) -> String {
        guard let id, !id.isEmpty else { return "Silence" }
        return allEntries.first { $0.id == id }?.title ?? "Silence"
    }

    /// The `Session.mode` a Watch-initiated session records for a selection.
    /// Must agree with the phone's `SoundCatalog.mode(for:)` — locked by test.
    public static func mode(for id: String?) -> String {
        guard let id, !id.isEmpty else { return "silence" }
        if id.hasPrefix("guided") { return "guided" }
        if ["rain", "ocean", "forest", "campfire"].contains(id) { return "nature" }
        if allEntries.contains(where: { $0.id == id }) { return "frequency" }
        return "silence"
    }
}
