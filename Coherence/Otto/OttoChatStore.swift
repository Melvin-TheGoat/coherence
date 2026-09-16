import Foundation

/// Otto's conversations, kept on the phone so leaving the chat does not end
/// it (Melvin, 2026-09-16: "it disappears if I leave the chat, which would
/// be very annoying for a user especially if they had a long discussion").
///
/// One file per conversation under Application Support, keyed by the session
/// the chat was opened from (or "profile" for the general chat). JSON, plain
/// Foundation. **Never synced**: a transcript quotes heart-rate numbers, and
/// the 5.1.3 split keeps those on the phone that recorded them. Deleted with
/// the session, and wholesale on sign-out and account deletion.
enum OttoChatStore {
    struct Saved: Codable, Equatable {
        struct Line: Codable, Equatable {
            var fromOtto: Bool
            var text: String
        }
        var lines: [Line]
        var updatedAt: Date
    }

    /// Lines kept per conversation. The model's window is small, so only the
    /// tail is replayed to it; the screen shows everything kept.
    static let maxLines = 80
    /// Turns (question + answer) replayed into the model's transcript when a
    /// chat is reopened. Enough to keep the thread; few enough to leave the
    /// window for new questions.
    static let replayedTurns = 6

    static func key(for sessionID: UUID?) -> String {
        sessionID?.uuidString ?? "profile"
    }

    static func load(key: String, directory: URL = defaultDirectory) -> Saved? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".json")) else { return nil }
        return try? decoder.decode(Saved.self, from: data)
    }

    static func save(_ lines: [Saved.Line], key: String, directory: URL = defaultDirectory, now: Date = Date()) {
        let kept = Array(lines.suffix(maxLines))
        guard let data = try? encoder.encode(Saved(lines: kept, updatedAt: now)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(key + ".json"), options: .atomic)
    }

    static func delete(key: String, directory: URL = defaultDirectory) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(key + ".json"))
    }

    static func deleteAll(directory: URL = defaultDirectory) {
        try? FileManager.default.removeItem(at: directory)
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Otto", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
