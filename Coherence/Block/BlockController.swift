import Foundation
import SwiftUI
import Combine
import FamilyControls
import UserNotifications

/// Block in the app: reads and changes the blockers, asks for Screen Time and
/// notification access, takes "Not now" passes, releases a window when a
/// session lands, and asks for one of Otto's screens when the shield's "Ask
/// Otto" notification is tapped.
///
/// **Every change goes through `commit`**, which saves to the App Group,
/// re-registers the schedules when the blockers changed, and brings the
/// shields in line. The monitor extension does the same `reconcile` on its
/// own wakes, so the two can never disagree about what should be held.
@MainActor
final class BlockController: ObservableObject {
    static let shared = BlockController()

    @Published private(set) var state: BlockState
    @Published private(set) var authorization: AuthorizationStatus
    /// Set when an Otto screen should open (the notification was tapped, or
    /// an "Ask Otto" went unanswered). ContentView presents it.
    @Published var interventionRequest: Date?
    /// Something Screen Time refused, in words, for the Block tab.
    @Published var problem: String?
    /// Whether 808 may post notifications. Without them "Ask Otto" can only
    /// send the person to 808 by hand, so the tab says so.
    @Published private(set) var notificationsAllowed = true

    private var authorizationWatch: AnyCancellable?

    private init() {
        state = BlockStore.load()
        authorization = AuthorizationCenter.shared.authorizationStatus
        #if DEBUG
        #if targetEnvironment(simulator)
        let testByDefault = true
        #else
        let testByDefault = false
        #endif
        testMode = ProcessInfo.processInfo.environment["PREVIEW_BLOCK"] != nil
            || (UserDefaults.standard.object(forKey: Self.testModeKey) as? Bool ?? testByDefault)
        #endif
        seedDefaultIfNeeded()
        #if DEBUG
        seedPreview()
        #endif
        // Screen Time access can be granted, revoked and granted again from
        // Settings at any time (the review of 2026-09-22). A revoke drops the
        // schedules; a grant, first or again, has to register them.
        authorizationWatch = AuthorizationCenter.shared.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.authorizationChanged(to: status) }
    }

    private func authorizationChanged(to status: AuthorizationStatus) {
        let was = authorization
        authorization = status
        #if DEBUG
        if testMode { return }
        #endif
        if status == .approved && was != .approved {
            commit(reschedule: true)
        } else if status != .approved && was == .approved {
            BlockSchedule.stopAll()
        }
    }

    #if DEBUG
    /// Block without Screen Time (Melvin, 2026-09-22: on the simulator,
    /// allowing Screen Time asks for a passcode nobody has, and a simulator
    /// cannot draw a shield anyway). Screen Time is treated as allowed and
    /// never called, a blocker switched on counts as having apps, and the
    /// Block tab plays the shield's part with a stand-in whose "Ask Otto"
    /// sends the real notification. On by default in the simulator, off on a
    /// phone, and switchable on the Block tab in any development build.
    @Published private(set) var testMode = false
    private static let testModeKey = "block.testMode.v1"

    func setTestMode(_ on: Bool) {
        testMode = on
        UserDefaults.standard.set(on, forKey: Self.testModeKey)
        refresh()
    }

    /// Test mode: forget today's releases and passes, so the apps are held
    /// again without waiting for tomorrow.
    func holdAgain(now: Date = Date()) {
        guard testMode else { return }
        state.releases.removeAll { now.timeIntervalSince($0.at) < 36 * 3600 }
        state.passes.removeAll { now.timeIntervalSince($0.start) < 36 * 3600 }
        commit(reschedule: false)
    }

    /// `PREVIEW_BLOCK=1` (simulator review) turns test mode on with Mindful
    /// day already set up and holding. `PREVIEW_BLOCK=empty` keeps the fresh
    /// state.
    private func seedPreview() {
        guard let preview = ProcessInfo.processInfo.environment["PREVIEW_BLOCK"], preview != "empty",
              let i = state.blockers.firstIndex(where: { $0.kind == .mindfulDay }) else { return }
        state.blockers[i].hasApps = true
        state.blockers[i].isOn = true
    }
    #endif

    var authorized: Bool {
        #if DEBUG
        if testMode { return true }
        #endif
        return authorization == .approved
    }

    // MARK: - Reading

    func blocker(_ id: UUID) -> Blocker? { state.blocker(id) }

    func selection(for id: UUID) -> FamilyActivitySelection { BlockStore.selection(for: id) }

    func holding(at now: Date = Date()) -> [Blocker] { BlockRules.holding(state, at: now) }

    func holds(_ blocker: Blocker, at now: Date = Date()) -> Bool {
        BlockRules.holds(blocker, in: state, at: now)
    }

    /// The windows a "Not now" went unanswered in, for Otto's glow.
    var notNowWindows: [DateInterval] { BlockRules.notNowWindows(state) }

    // MARK: - Access

    /// Screen Time, for the person themselves (`.individual`): the system
    /// sheet, then Face ID or the passcode.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            NSLog("Block: Screen Time authorization failed: %@", String(describing: error))
        }
        // Through the same path as a change made in Settings, so a grant
        // (first, or after a revoke) registers the schedules.
        authorizationChanged(to: AuthorizationCenter.shared.authorizationStatus)
        return authorized
    }

    /// "Otto wants a word" is a notification, so Block needs them. Asks only
    /// if nobody has been asked yet.
    func requestNotificationsIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Changing

    /// Saves a blocker, with its apps when they were just picked. A blocker
    /// with no apps cannot be on.
    func save(_ blocker: Blocker, selection: FamilyActivitySelection?) {
        var saved = blocker
        if let selection {
            BlockStore.setSelection(selection, for: saved.id)
            saved.hasApps = !selection.isEmptySelection
            #if DEBUG
            // The simulator's picker has no real apps to offer.
            if testMode { saved.hasApps = true }
            #endif
        }
        #if DEBUG
        // The simulator's picker has no real apps, so switching it on in the
        // editor counts as having them, the way the card's switch does.
        if testMode && saved.isOn { saved.hasApps = true }
        #endif
        if !saved.hasApps { saved.isOn = false }
        if let i = state.blockers.firstIndex(where: { $0.id == saved.id }) {
            state.blockers[i] = saved
        } else {
            state.blockers.append(saved)
        }
        commit(reschedule: true)
    }

    func setOn(_ id: UUID, _ on: Bool) {
        guard let i = state.blockers.firstIndex(where: { $0.id == id }) else { return }
        #if DEBUG
        if testMode && on { state.blockers[i].hasApps = true }
        #endif
        state.blockers[i].isOn = on && state.blockers[i].hasApps
        commit(reschedule: true)
    }

    func delete(_ id: UUID) {
        state.blockers.removeAll { $0.id == id }
        BlockStore.removeSelection(for: id)
        if authorized { BlockShields.lift(id) }
        commit(reschedule: true)
    }

    /// "Not now" for `minutes`: every holding blocker opens
    /// for that long, and Screen Time is told when to close them again.
    ///
    /// **Fails closed** (the review of 2026-09-22): a pass whose end Screen
    /// Time refuses to schedule would leave the apps open for the rest of the
    /// window, all day on Mindful day. Such a pass is taken back and the apps
    /// stay held. The state is saved before asking, because an interval that
    /// starts in the past can wake the monitor at once, and it must find the
    /// pass.
    @discardableResult
    func takePass(minutes: Int, now: Date = Date()) -> [UUID] {
        var opened = BlockRules.takePass(minutes: minutes, in: &state, at: now)
        #if DEBUG
        if testMode { commit(reschedule: false); return opened }
        #endif
        guard authorized else {
            state.passes.removeAll { pass in opened.contains(pass.blockerID) && pass.start == now }
            return []
        }
        BlockStore.save(state)
        for id in opened {
            guard let i = state.passes.lastIndex(where: { $0.blockerID == id && $0.start == now }) else { continue }
            if let end = BlockSchedule.schedulePassEnd(for: id, at: state.passes[i].end, now: now) {
                state.passes[i].end = end
            } else {
                state.passes.remove(at: i)
                opened.removeAll { $0 == id }
                problem = "Otto couldn't open your apps just now. Try again in a moment."
            }
        }
        commit(reschedule: false)
        return opened
    }

    /// A session landed: it opens the rest of every window it counts for.
    func recordSession(endingAt end: Date, durationSec: Int) {
        let released = BlockRules.recordSession(endingAt: end, durationSec: durationSec, in: &state)
        if !released.isEmpty {
            commit(reschedule: false)
            clearDeliveredAsk()
        }
    }

    /// "Otto wants a word" lingers in Notification Center after the apps are
    /// open, and tapping it later would open Otto about nothing.
    func clearDeliveredAsk() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [BlockAsk.notificationID])
    }

    /// Sessions that ended while 808 was closed (a Watch session delivered
    /// on the next launch, say). Idempotent, so calling it on every return to
    /// the foreground is fine.
    func catchUp(with sessions: [(end: Date, durationSec: Int)], now: Date = Date()) {
        var released: [UUID] = []
        for session in sessions where now.timeIntervalSince(session.end) < 36 * 3600 {
            released += BlockRules.recordSession(endingAt: session.end, durationSec: session.durationSec,
                                                 in: &state)
        }
        if !released.isEmpty { commit(reschedule: false) }
    }

    func noteInterventionShown(_ kind: InterventionKind, at now: Date = Date()) {
        state.recentInterventions.append(kind.rawValue)
        state.lastInterventionAt = now
        commit(reschedule: false)
    }

    var recentInterventions: [InterventionKind] {
        state.recentInterventions.compactMap(InterventionKind.init(rawValue:))
    }

    /// Re-reads what the extensions wrote (asks, daily limits) and puts the
    /// shields right. On every return to the foreground.
    func refresh(now: Date = Date()) {
        let fresh = BlockStore.load()
        state.asks = fresh.asks
        state.limitHits = fresh.limitHits
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            notificationsAllowed = allowed || settings.authorizationStatus == .notDetermined
            BlockStore.setNotificationsAllowed(allowed)
        }
        if authorized {
            #if DEBUG
            if testMode { return }
            #endif
            BlockShields.reconcile(now: now)
        }
    }

    /// Asks for an Otto screen, from the notification or an unanswered ask.
    func requestIntervention() {
        interventionRequest = Date()
    }

    var hasUnansweredAsk: Bool { BlockRules.unansweredAsk(state, at: Date()) }

    /// Tapping the notification both delivers it AND brings 808 to the
    /// foreground, and each of those asks for Otto. The first one wins; the
    /// other, a moment later, would queue a second screen behind the first.
    private var lastPresentation: Date?

    func claimPresentation(now: Date = Date()) -> Bool {
        if let last = lastPresentation, now.timeIntervalSince(last) < 15 { return false }
        lastPresentation = now
        return true
    }

    private func commit(reschedule: Bool) {
        BlockRules.prune(&state, now: Date())
        BlockStore.save(state)
        #if DEBUG
        if testMode { return }
        #endif
        guard authorized else { return }
        if reschedule {
            let refused = BlockSchedule.sync(state)
            problem = refused.isEmpty ? nil
                : "Screen Time didn't take \(refused.joined(separator: ", ")). Try saving it again."
        }
        BlockShields.reconcile()
    }

    /// Mindful day, set up and waiting, for everyone (Melvin, 2026-09-22).
    /// Once: deleting it does not bring it back.
    private func seedDefaultIfNeeded() {
        guard !state.seededDefault else { return }
        state.blockers.insert(Blocker.preset(.mindfulDay), at: 0)
        state.seededDefault = true
        BlockStore.save(state)
    }
}

/// Whether this person may switch Block on. Paid (Melvin, 2026-09-22), except
/// in development builds, where no products load and the side-by-side beta
/// could otherwise never test it. `BLOCK_PAYWALL=1` puts the paywall back for
/// reviewing it on a simulator.
enum BlockAccess {
    static func allowed(_ entitlements: Entitlements) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BLOCK_PAYWALL"] == "1" { return entitlements.block }
        return true
        #else
        return entitlements.block
        #endif
    }
}

/// Routes a tap on "Otto wants a word" into the app.
///
/// **808 had no notification delegate before Block**, and the reminder
/// behaves as it always did: shown only when 808 is not on screen, and
/// tapping it simply opens the app.
final class BlockNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BlockNotifications()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isBlock = notification.request.content.userInfo["block"] != nil
        completionHandler(isBlock ? [.banner, .sound] : [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["block"] != nil {
            Task { @MainActor in BlockController.shared.requestIntervention() }
        }
        completionHandler()
    }
}
