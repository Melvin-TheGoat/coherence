import Foundation

/// What the home screen widget shows, written by the app and read by the
/// widget extension (OttoWidget/, 2026-10-05). The widget computes nothing
/// itself: Otto's glow needs the session history, the "Not now" windows and
/// the day the glow started counting, and only the app holds those. So the
/// app works out every number and line, and the widget only picks the day
/// and paints the valley for the hour.
///
/// **A widget cannot wake the app at midnight**, so the snapshot carries the
/// next few days as well, each worked out as if no session happens before
/// it (`OttoWidgetFeed`). A missed day then shows on the home screen the
/// morning it happens, exactly as Home would show it, without 808 being
/// opened. The first session after that rewrites the snapshot.
///
/// Compiled into the widget, the app and the tests. Foundation only.
///
/// **Nothing from Screen Time is written here** (Apple's Family Controls
/// terms): the glow level already has the "Not now" windows priced in, the
/// same number Home shows, and no app, window or blocker is named.
struct OttoWidgetSnapshot: Codable, Equatable {
    struct Day: Codable, Equatable {
        /// The midnight that begins this day.
        var start: Date
        /// Otto's glow, 0 to 100.
        var level: Int
        /// Days practised in the run still alive (0 = no flame).
        var streak: Int
        /// The line Otto says on the medium widget.
        var line: String
    }

    /// Whether this person has 808. A widget left on the home screen after a
    /// membership ends shows only a way back into 808, never Otto's numbers
    /// (808 is premium only).
    var member: Bool
    /// Today, then the days after it if nobody meditates in between.
    var days: [Day]
    var written: Date

    /// The day to show at `date`: the latest one that has begun. Past the
    /// last projected day the last one stands, which is the right Otto for a
    /// widget on a phone 808 has not been opened on for days.
    func day(at date: Date) -> Day? {
        days.last { $0.start <= date } ?? days.first
    }

    /// The glow's stage, 1 (Withered) to 7 (Nirvana), from the same bands as
    /// `OttoAura.Stage`, which the widget does not compile. Locked against it
    /// by `OttoWidgetTests`.
    static func stage(level: Int) -> Int {
        switch level {
        case ..<15: return 1
        case ..<30: return 2
        case ..<45: return 3
        case ..<60: return 4
        case ..<75: return 5
        case ..<90: return 6
        default: return 7
        }
    }
}

/// Where the snapshot lives: the App Group the app already shares with
/// Block's extensions. The ID is derived from the bundle ID the way
/// `BlockGroup` derives it (BlockKit is not compiled into the widget), so the
/// side-by-side beta keeps its own snapshot and its own Otto.
enum OttoWidgetShelf {
    static let key = "widget.otto.v1"
    /// The widget's kind, for reloading it from the app.
    static let kind = "OttoWidget"
    /// DEBUG only: the hour the widget paints its sky at (`VALLEY_HOUR`).
    static let debugHourKey = "widget.debug.hour"

    static var groupID: String {
        var bundle = Bundle.main.bundleIdentifier ?? "com.lockout.meditate808"
        // An extension's ID is the app's plus one component.
        if Bundle.main.bundleURL.pathExtension == "appex" {
            bundle = bundle.split(separator: ".").dropLast().joined(separator: ".")
        }
        return "group." + bundle
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    static func read(from defaults: UserDefaults? = defaults) -> OttoWidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OttoWidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot, and says whether it changed anything. The app
    /// reloads the widget only when it did, so opening 808 ten times a day
    /// does not spend the widget's refreshes on the same picture.
    @discardableResult
    static func write(_ snapshot: OttoWidgetSnapshot, to defaults: UserDefaults? = defaults) -> Bool {
        let old = read(from: defaults)
        // `written` changes every time, so compare everything else.
        if let old, old.member == snapshot.member, old.days == snapshot.days { return false }
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults?.set(data, forKey: key)
        return true
    }
}
