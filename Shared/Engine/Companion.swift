import Foundation

/// The forms Otto is reborn into as people meditate (Melvin, 2026-11-10,
/// `mockups/level-up.html`): the sloth everyone starts as, then a red panda,
/// a tiger, a phoenix and a dragon. **It is always Otto**, never a new
/// friend: every name on screen says "Otto" ("Otto was reborn as a red
/// panda").
///
/// **A form arrives at LIFETIME points**, never the balance. Points are
/// spent on hats, so a balance can fall; lifetime points only climb, so the
/// Shop never slows his next form. Lifetime points are the same points as
/// everywhere else: one per whole minute meditated (hand-logged sessions earn
/// none) plus each week finished with a friend (`OttoPoints.lifetime`).
///
/// Each form keeps Otto's seven glow stages and their rules unchanged
/// (`OttoAura`). Pure Foundation: compiled into the app, the Watch and the
/// tests.
enum Companion: String, CaseIterable, Codable, Identifiable, Comparable {
    case otto, redPanda, tiger, phoenix, dragon

    var id: String { rawValue }

    /// Lifetime points that bring this form (Melvin, 2026-11-10: about a year
    /// at 15 minutes a day for the dragon).
    var threshold: Int {
        switch self {
        case .otto: return 0
        case .redPanda: return 300
        case .tiger: return 800
        case .phoenix: return 2_200
        case .dragon: return 5_500
        }
    }

    /// The creature, lower case, for sentences ("reborn as a red panda").
    var creature: String {
        switch self {
        case .otto: return "sloth"
        case .redPanda: return "red panda"
        case .tiger: return "tiger"
        case .phoenix: return "phoenix"
        case .dragon: return "dragon"
        }
    }

    /// The creature with its article: "a red panda", "a tiger".
    var withArticle: String { "a \(creature)" }

    /// The creature for a title: "Red panda", "Sloth".
    var title: String { creature.prefix(1).uppercased() + creature.dropFirst() }

    /// The file and asset stem: `CompanionRedPanda.riv`, `CompanionRedPanda4`.
    /// Otto has his own (`OttoAura.riv`, `OttoAura4`).
    var key: String {
        switch self {
        case .otto: return "Otto"
        case .redPanda: return "RedPanda"
        case .tiger: return "Tiger"
        case .phoenix: return "Phoenix"
        case .dragon: return "Dragon"
        }
    }

    /// The still for a glow stage (1 to 7) in the app's catalog.
    func stillName(stage: Int) -> String {
        let s = min(max(stage, 1), 7)
        return self == .otto ? "OttoAura\(s)" : "Companion\(key)\(s)"
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (a: Companion, b: Companion) -> Bool { a.order < b.order }

    /// The profile-picture preset this form unlocks (Melvin, 2026-11-12):
    /// `avatar-form-redpanda.jpg` and so on. Otto has none of his own here;
    /// his picture (`otto`) is free to everyone. Ids carry a `form-` prefix so
    /// they never collide with the free `red-panda` preset 1.4 offered (removed 2026-11-12).
    var pictureID: String? { self == .otto ? nil : "form-\(key.lowercased())" }

    /// The form whose picture this preset is, if it is one.
    static func forPicture(_ presetID: String) -> Companion? {
        allCases.first { $0.pictureID == presetID }
    }

    /// A form's picture is locked until its rebirth has played on this phone
    /// (`CompanionBook.announced`), the same moment it joins Otto's forms.
    /// Every other preset is never locked.
    static func pictureLocked(_ presetID: String, announced: [Companion]) -> Bool {
        guard let form = forPicture(presetID) else { return false }
        return !announced.contains(form)
    }

    /// What a locked picture says when tapped:
    /// "Unlocks when Otto becomes a red panda · 300 points".
    var pictureUnlockNote: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        let points = f.string(from: NSNumber(value: threshold)) ?? "\(threshold)"
        return "Unlocks when Otto becomes \(withArticle) · \(points) points"
    }

    /// Every form these lifetime points have reached, Otto first.
    static func reached(lifetime: Int) -> [Companion] {
        allCases.filter { $0.threshold <= lifetime }
    }

    /// The next form these points have not reached, if any.
    static func next(lifetime: Int) -> Companion? {
        allCases.first { $0.threshold > lifetime }
    }
}

/// What this phone remembers about Otto's forms: which he wears, which
/// rebirths have played, and when each one played. **Per device, in
/// UserDefaults**, like the glow's own start (`OttoAura.glowStart`) and the
/// announced awards: everything else is derived from sessions, which sync,
/// so a new phone works the forms out again and plays each rebirth once
/// more. A synced field would need a CloudKit Production promotion for a
/// cosmetic choice; the widget and the Watch read the form from the
/// snapshot the app writes, so they need nothing from here.
enum CompanionBook {
    static let chosenKey = "companion.chosen.v1"
    static let announcedKey = "companion.announced.v1"
    static let restartsKey = "companion.glowRestarts.v1"

    /// Forms whose rebirth has played on this phone, in the order they played.
    static func announced(_ defaults: UserDefaults = .standard) -> [Companion] {
        ((defaults.array(forKey: announcedKey) as? [String]) ?? []).compactMap(Companion.init(rawValue:))
    }

    /// Rebirths owed: every form the points have reached whose moment has not
    /// played, in order (Otto never: everyone starts as him). A member who
    /// already has the points for two sees the red panda, then the tiger.
    static func pending(lifetime: Int, announced: [Companion]) -> [Companion] {
        Companion.reached(lifetime: lifetime).filter { $0 != .otto && !announced.contains($0) }
    }

    /// Forms that can be chosen in Otto's forms: Otto, and every rebirth that
    /// has played. A form whose moment is still owed is not offered, so the
    /// picker never spoils it.
    static func available(_ defaults: UserDefaults = .standard) -> [Companion] {
        [.otto] + announced(defaults).sorted()
    }

    /// The form he wears. Falls back to Otto when nothing (or something no
    /// longer available) is stored.
    static func chosen(_ defaults: UserDefaults = .standard) -> Companion {
        guard let raw = defaults.string(forKey: chosenKey), let form = Companion(rawValue: raw),
              available(defaults).contains(form) else { return .otto }
        return form
    }

    /// Switching keeps today's glow (it belongs to the practice, not to a
    /// form). Returns whether anything changed.
    @discardableResult
    static func choose(_ form: Companion, defaults: UserDefaults = .standard) -> Bool {
        guard available(defaults).contains(form), chosen(defaults) != form else { return false }
        defaults.set(form.rawValue, forKey: chosenKey)
        return true
    }

    /// The rebirth played: the form joins Otto's forms, he wears it, and his
    /// glow restarts at 50 (Steady) from this moment (`glowRestart`). Only
    /// the FIRST time a form is reached; a second call changes nothing.
    /// Returns whether it was new.
    @discardableResult
    static func announce(_ form: Companion, now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard form != .otto else { return false }
        var list = announced(defaults)
        guard !list.contains(form) else { return false }
        list.append(form)
        defaults.set(list.map(\.rawValue), forKey: announcedKey)
        var restarts = (defaults.dictionary(forKey: restartsKey) as? [String: Date]) ?? [:]
        restarts[form.rawValue] = now
        defaults.set(restarts, forKey: restartsKey)
        defaults.set(form.rawValue, forKey: chosenKey)
        return true
    }

    /// The moment the glow last restarted at 50: the latest rebirth on this
    /// phone. Nil before the first. Passed to `OttoAura.level(restart:)`.
    static func glowRestart(_ defaults: UserDefaults = .standard) -> Date? {
        ((defaults.dictionary(forKey: restartsKey) as? [String: Date]) ?? [:]).values.max()
    }

    /// A fresh start on this phone (sign-out, account deletion): back to Otto.
    static func forget(_ defaults: UserDefaults = .standard) {
        for key in [chosenKey, announcedKey, restartsKey] { defaults.removeObject(forKey: key) }
    }
}
