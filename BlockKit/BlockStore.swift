import Foundation
import FamilyControls
import ManagedSettings
import UserNotifications

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
    static func reconcile(now: Date = Date()) {
        let state = BlockStore.load()
        for blocker in state.blockers {
            if BlockRules.holds(blocker, in: state, at: now) {
                hold(blocker)
            } else {
                lift(blocker.id)
            }
        }
        let current = Set(state.blockers.map(\.id.uuidString))
        for raw in BlockStore.knownStores() where !current.contains(raw) {
            if let id = UUID(uuidString: raw) { lift(id) }
        }
    }
}

/// "Ask Otto": the tap is recorded and "Otto wants a word" is sent, because a
/// shield cannot open an app. The shield's button and the app's DEBUG test
/// mode both come through here, so a rehearsal on the simulator sends exactly
/// what the phone will.
enum BlockAsk {
    static let notificationID = "808.block.ask"

    static func post(completion: @escaping () -> Void = {}) {
        BlockStore.appendAsk()
        let content = UNMutableNotificationContent()
        content.title = "Otto wants a word"
        content.body = "Tap to talk it through."
        content.sound = .default
        // Through Focus, which is when it matters most.
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["block": "ask"]
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in completion() }
    }
}

/// What a held app's shield says, shared with the test mode's stand-in for it.
enum BlockShieldWords {
    static func title(for name: String?) -> String {
        name.map { "Otto's holding \($0)" } ?? "Otto's holding this one"
    }

    /// With notifications off the notification never comes, so the shield
    /// sends the person to 808 by hand, where an unanswered ask opens Otto.
    static func subtitle(asked: Bool, notificationsAllowed: Bool) -> String {
        guard asked else { return "Meditate first, or ask him for a few minutes." }
        return notificationsAllowed
            ? "Otto's on his way. Tap the notification up top."
            : "Open 808 and Otto will meet you there."
    }

    static func primary(asked: Bool) -> String { asked ? "Send it again" : "Ask Otto" }
    static let secondary = "Close"
}

