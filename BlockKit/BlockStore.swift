import Foundation
import FamilyControls
import ManagedSettings
import UserNotifications
import os

// BlockKit: the Screen Time half of Block, compiled into the app and all three
// extensions (the DeviceActivity monitor, the shield's look, the shield's
// buttons). The rules it applies are `BlockRules` in Shared/Block.
//
// **Nothing here leaves the phone** (Apple's Family Controls terms, accepted
// with the entitlement request, 2026-09-22). The picked apps are opaque tokens
// even to us, and none of this is sent to PostHog, Friends or any server.

/// The App Group every Block process shares. Derived from the bundle ID, so
/// the side-by-side beta (`com.lockout.meditate808.dev`, `tools/beta_install.sh`)
/// keeps its own and never shares a phone's blockers with the App Store app.
enum BlockGroup {
    static var id: String {
        var bundle = Bundle.main.bundleIdentifier ?? "com.lockout.meditate808"
        // An extension's ID is the app's plus one component.
        if Bundle.main.bundleURL.pathExtension == "appex" {
            bundle = bundle.split(separator: ".").dropLast().joined(separator: ".")
        }
        return "group." + bundle
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

/// Block's memory, in the App Group.
///
/// **Each process writes only its own keys.** The app owns the state (the
/// blockers, passes, releases); the shield's buttons own the asks; the
/// monitor owns the daily-limit hits. Separate keys mean a tap on the shield
/// can never be lost to the app saving the state a moment later.
enum BlockStore {
    private static let stateKey = "block.state.v1"
    private static let asksKey = "block.asks.v1"
    private static let limitsKey = "block.limits.v1"
    private static let storesKey = "block.stores.v1"
    private static let schedulesKey = "block.schedules.v1"
    private static let notificationsKey = "block.notifications.v1"
    private static func selectionKey(_ id: UUID) -> String { "block.selection.\(id.uuidString)" }

    static func load() -> BlockState {
        let defaults = BlockGroup.defaults
        let raw = defaults?.data(forKey: stateKey)
        var state = decode(BlockState.self, raw) ?? BlockState()
        // The decoder takes a default for anything missing or new, so this is
        // corruption, not a version change. Keep the bytes rather than let the
        // next save write an empty state over them.
        if let raw, decode(BlockState.self, raw) == nil,
           defaults?.data(forKey: stateKey + ".unreadable") == nil {
            defaults?.set(raw, forKey: stateKey + ".unreadable")
        }
        state.asks = decode([Date].self, defaults?.data(forKey: asksKey)) ?? []
        state.limitHits = decode([BlockLimitHit].self, defaults?.data(forKey: limitsKey)) ?? []
        return state
    }

    /// The app's own fields. Asks and limit hits are written by the
    /// extensions that own them, through the two functions below.
    static func save(_ state: BlockState) {
        var owned = state
        owned.asks = []
        owned.limitHits = []
        BlockGroup.defaults?.set(try? JSONEncoder().encode(owned), forKey: stateKey)
        // Every blocker that has ever existed, so its shield can be lifted
        // after it is gone (or after a state that could not be read).
        let known = Set(knownStores()).union(state.blockers.map(\.id.uuidString))
        BlockGroup.defaults?.set(Array(known), forKey: storesKey)
    }

    static func knownStores() -> [String] {
        BlockGroup.defaults?.stringArray(forKey: storesKey) ?? []
    }

    /// What each blocker's window was registered with, so a sync restarts
    /// only what changed. App-owned.
    static func scheduleSignatures() -> [String: String] {
        (BlockGroup.defaults?.dictionary(forKey: schedulesKey) as? [String: String]) ?? [:]
    }

    static func setScheduleSignatures(_ signatures: [String: String]) {
        BlockGroup.defaults?.set(signatures, forKey: schedulesKey)
    }

    /// Whether 808 may post notifications, written by the app on every
    /// return to the foreground, read by the shield: with them off, "Ask
    /// Otto" can only send the person to 808 by hand.
    static var notificationsAllowed: Bool {
        (BlockGroup.defaults?.object(forKey: notificationsKey) as? Bool) ?? true
    }

    static func setNotificationsAllowed(_ allowed: Bool) {
        BlockGroup.defaults?.set(allowed, forKey: notificationsKey)
    }

    /// The shield's "Ask Otto".
    static func appendAsk(_ date: Date = Date()) {
        var asks = decode([Date].self, BlockGroup.defaults?.data(forKey: asksKey)) ?? []
        asks.append(date)
        asks = Array(asks.suffix(40))
        BlockGroup.defaults?.set(try? JSONEncoder().encode(asks), forKey: asksKey)
    }

    /// The monitor's "the daily limit ran out".
    static func appendLimitHit(_ id: UUID, at now: Date = Date()) {
        var state = BlockState()
        state.limitHits = decode([BlockLimitHit].self, BlockGroup.defaults?.data(forKey: limitsKey)) ?? []
        BlockRules.recordLimitHit(id, at: now, in: &state)
        let kept = state.limitHits.filter { now.timeIntervalSince($0.day) < 45 * 86_400 }
        BlockGroup.defaults?.set(try? JSONEncoder().encode(kept), forKey: limitsKey)
    }

    // MARK: The picked apps

    static func selection(for id: UUID) -> FamilyActivitySelection {
        decode(FamilyActivitySelection.self, BlockGroup.defaults?.data(forKey: selectionKey(id)))
            ?? FamilyActivitySelection()
    }

    static func setSelection(_ selection: FamilyActivitySelection, for id: UUID) {
        BlockGroup.defaults?.set(try? JSONEncoder().encode(selection), forKey: selectionKey(id))
    }

    static func removeSelection(for id: UUID) {
        BlockGroup.defaults?.removeObject(forKey: selectionKey(id))
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension FamilyActivitySelection {
    /// Whether anything at all was picked.
    var isEmptySelection: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    /// How many things were picked, for "4 apps" on a card.
    var pickedCount: Int {
        applicationTokens.count + categoryTokens.count + webDomainTokens.count
    }
}

/// Screen Time's shields, one named store per blocker so each can be lifted
/// on its own.
enum BlockShields {
    private static func store(_ id: UUID) -> ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("808.blocker.\(id.uuidString)"))
    }

    static func hold(_ blocker: Blocker) {
        let picked = BlockStore.selection(for: blocker.id)
        let settings = store(blocker.id)
        settings.shield.applications = picked.applicationTokens.isEmpty ? nil : picked.applicationTokens
        settings.shield.applicationCategories = picked.categoryTokens.isEmpty
            ? nil : .specific(picked.categoryTokens)
        settings.shield.webDomains = picked.webDomainTokens.isEmpty ? nil : picked.webDomainTokens
        settings.shield.webDomainCategories = picked.categoryTokens.isEmpty
            ? nil : .specific(picked.categoryTokens)
    }

    static func lift(_ id: UUID) {
        store(id).clearAllSettings()
    }

    /// Every blocker's shields brought in line with the rules at `now`. Safe
    /// to call from anywhere, any number of times: it only ever sets what
    /// the rules say. A store left by a blocker that no longer exists is
    /// lifted, so nothing stays shielded with no way to open it.
    ///
    /// Each write is a synchronous call to Screen Time's daemon: the app
    /// makes this call off the main thread (`ScreenTimeWork`). Returns how
    /// many stores it held and lifted, for the app's log.
    @discardableResult
    static func reconcile(now: Date = Date()) -> (held: Int, lifted: Int) {
        let state = BlockStore.load()
        var held = 0, lifted = 0
        for blocker in state.blockers {
            if BlockRules.holds(blocker, in: state, at: now) {
                hold(blocker)
                held += 1
            } else {
                lift(blocker.id)
                lifted += 1
            }
        }
        let current = Set(state.blockers.map(\.id.uuidString))
        for raw in BlockStore.knownStores() where !current.contains(raw) {
            if let id = UUID(uuidString: raw) { lift(id); lifted += 1 }
        }
        return (held, lifted)
    }
}

/// "Ask Otto": the tap is recorded and "Otto wants a word" is sent, because a
/// shield cannot open an app. The shield's button and the app's DEBUG test
/// mode both come through here, so a rehearsal on the simulator sends exactly
/// what the phone will.
enum BlockAsk {
    /// Every ask gets its own identifier under this prefix (2026-10-08).
    /// One fixed identifier made each ask REPLACE the last one still in
    /// Notification Center, and iOS can deliver a replacement late and
    /// quietly; Melvin saw about five seconds between the tap and the banner.
    static let notificationPrefix = "808.block.ask"
    private static let log = Logger(subsystem: "com.lockout.meditate808", category: "Block")

    /// `completion` runs once the notification is handed over, or after two
    /// seconds, whichever is first: the shield's button waits on it before
    /// the shield draws again, and it must never wait on a slow notification
    /// server (2026-10-06). The ask is recorded first either way, so opening
    /// 808 by hand still finds Otto waiting.
    static func post(completion: @escaping () -> Void = {}) {
        BlockStore.appendAsk()
        let content = UNMutableNotificationContent()
        content.title = "Otto wants a word"
        content.body = "Tap to talk it through."
        content.sound = .default
        // Through Focus, which is when it matters most.
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["block": "ask"]
        let id = "\(notificationPrefix).\(Int(Date().timeIntervalSince1970 * 1000))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        let finish = OneShot(completion)
        let began = Date()
        let center = UNUserNotificationCenter.current()
        // Older asks still in Notification Center go, without holding up
        // this one: the new banner is the only one worth tapping.
        center.getDeliveredNotifications { delivered in
            let old = delivered.map(\.request.identifier)
                .filter { $0.hasPrefix(notificationPrefix) && $0 != id }
            if !old.isEmpty { center.removeDeliveredNotifications(withIdentifiers: old) }
        }
        center.add(request) { error in
            let took = Date().timeIntervalSince(began)
            log.info("Ask Otto: notification handed over in \(took, format: .fixed(precision: 2), privacy: .public)s, error: \(error.map { String(describing: $0) } ?? "none", privacy: .public)")
            finish.run()
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
            if finish.run() { log.error("Ask Otto: the notification server took over 2 s; the shield went on without it") }
        }
    }
}

extension BlockAsk {
    /// Every "Otto wants a word" still in Notification Center.
    static func clearDelivered() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(notificationPrefix) }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }
}

/// A completion that runs once, whichever caller gets there first.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var work: (() -> Void)?

    init(_ work: @escaping () -> Void) { self.work = work }

    /// Runs it if nobody has yet; says whether this call did.
    @discardableResult
    func run() -> Bool {
        lock.lock()
        let pending = work
        work = nil
        lock.unlock()
        pending?()
        return pending != nil
    }
}

/// What a held app's shield says, shared with the test mode's stand-in for it.
/// The line and colour come from `ShieldLines`, a new pick each time a shield
/// appears (Aziz, 2026-10-06).
enum BlockShieldWords {
    /// The shield's own key (each process writes only its own keys): the
    /// line and colour it picked, and when. Screen Time asks the shield for
    /// its configuration more than once while it is up (and again after
    /// "Ask Otto"), so a pick is kept for 90 seconds; past that, opening the
    /// app again draws a new one.
    private static let lookKey = "block.shieldLook.v1"
    static let lookLifetime: TimeInterval = 90

    struct Look: Equatable {
        let line: ShieldLines.Line
        let palette: ShieldLines.Palette
    }

    /// The look to show now. `remember: false` (the app's rehearsal stand-ins)
    /// draws without writing the shield's key.
    static func look(now: Date = Date(), remember: Bool = true) -> Look {
        let d = BlockGroup.defaults
        let saved = d?.array(forKey: lookKey) as? [Double]
        var pick: (line: Int, palette: Int)
        if let saved, saved.count == 3,
           now.timeIntervalSince1970 - saved[0] < lookLifetime,
           Int(saved[1]) < ShieldLines.all.count, Int(saved[2]) < ShieldLines.palettes.count {
            pick = (Int(saved[1]), Int(saved[2]))
        } else {
            let previous = (saved?.count == 3) ? (line: Int(saved![1]), palette: Int(saved![2])) : nil
            pick = ShieldLines.next(after: previous)
            if remember {
                d?.set([now.timeIntervalSince1970, Double(pick.line), Double(pick.palette)], forKey: lookKey)
            }
        }
        return Look(line: ShieldLines.all[pick.line], palette: ShieldLines.palettes[pick.palette])
    }

    static func title(for name: String?, look: Look) -> String {
        ShieldLines.fill(look.line.title, app: name)
    }

    /// Once asked, the shield says the notification is on its way. With
    /// notifications off it never comes, so the shield sends the person to
    /// 808 by hand, where an unanswered ask opens Otto.
    static func subtitle(for name: String?, look: Look, asked: Bool, notificationsAllowed: Bool) -> String {
        guard asked else { return ShieldLines.fill(look.line.subtitle, app: name) }
        return notificationsAllowed
            ? "Otto's on his way. Tap the notification up top."
            : "Open 808 and Otto will meet you there."
    }

    static func primary(asked: Bool) -> String { asked ? "Send it again" : "Ask Otto" }
    static let secondary = "Close"
}

