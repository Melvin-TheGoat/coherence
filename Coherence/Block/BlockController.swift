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
            ScreenTimeWork.run("stop every schedule") { BlockSchedule.stopAll() }
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
    /// Settings > Block (debug): hold every blocker's apps now, regardless of
    /// schedules and sessions (`BlockState.holdAll`). Turning it on also
    /// ends any "Not now" running, so the shield shows at once.
    var holdAll: Bool { state.holdAll }

    func setHoldAll(_ on: Bool, now: Date = Date()) {
        state.holdAll = on
        if on { state.passes.removeAll { $0.end > now } }
        commit(reschedule: false)
    }

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
        // `PREVIEW_BLOCK=full` (store shots) adds Wind down and a weekend
        // blocker, switched on: neither window is open on a weekday morning,
        // so their "Waiting" agrees with a 9:41 status bar.
        guard preview == "full" else { return }
        if !state.blockers.contains(where: { $0.kind == .windDown }) {
            var extra = Blocker.preset(.windDown)
            extra.hasApps = true
            extra.isOn = true
            state.blockers.append(extra)
        }
        if !state.blockers.contains(where: { $0.kind == .custom }) {
            state.blockers.append(Blocker(kind: .custom, name: "Weekend unplug", isOn: true,
                                          weekdays: [1, 7], hasApps: true, symbol: "leaf.fill"))
        }
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
        // No `.badge`: 808 never sets a badge, and asking for a permission
        // the app does not use is what App Review flags (App Review pass,
        // 2026-09-29).
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
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
        if authorized { ScreenTimeWork.run("lift a deleted blocker") { BlockShields.lift(id) } }
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
    ///
    /// Screen Time is asked off the main thread (`ScreenTimeWork`). A shield
    /// pass already waiting there can open the apps first, as the monitor
    /// waking could before; a refusal still takes the pass back a moment
    /// later and the apps are held again. Returns the ids asked for.
    @discardableResult
    func takePass(minutes: Int, now: Date = Date()) -> [UUID] {
        let opened = BlockRules.takePass(minutes: minutes, in: &state, at: now)
        #if DEBUG
        if testMode { commit(reschedule: false); return opened }
        #endif
        guard authorized else {
            state.passes.removeAll { pass in opened.contains(pass.blockerID) && pass.start == now }
            return []
        }
        BlockStore.save(state)
        let ends: [(UUID, Date)] = opened.compactMap { id in
            state.passes.last(where: { $0.blockerID == id && $0.start == now }).map { (id, $0.end) }
        }
        ScreenTimeWork.run("schedule \(ends.count) pass end(s)") {
            let scheduled = ends.map { ($0.0, BlockSchedule.schedulePassEnd(for: $0.0, at: $0.1, now: now)) }
            Task { @MainActor [weak self] in self?.applyPassEnds(scheduled, startedAt: now) }
        }
        return opened
    }

    /// What Screen Time said about each pass's end: the end it will wake the
    /// monitor at, or nil for a refusal, which takes the pass back.
    private func applyPassEnds(_ scheduled: [(UUID, Date?)], startedAt now: Date) {
        for (id, end) in scheduled {
            guard let i = state.passes.lastIndex(where: { $0.blockerID == id && $0.start == now }) else { continue }
            if let end {
                state.passes[i].end = end
            } else {
                state.passes.remove(at: i)
                problem = "Otto couldn't open your apps just now. Try again in a moment."
            }
        }
        commit(reschedule: false)
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
    ///
    /// `sessions` must be EVERY stored session that ended in the last 36
    /// hours: an opening in that span whose session is not in the list was
    /// deleted, and is taken back (`BlockRules.forgetReleases`).
    func catchUp(with sessions: [(end: Date, durationSec: Int)], now: Date = Date()) {
        var released: [UUID] = []
        let since = now.addingTimeInterval(-36 * 3600)
        for session in sessions where session.end >= since {
            released += BlockRules.recordSession(endingAt: session.end, durationSec: session.durationSec,
                                                 in: &state)
        }
        let forgot = BlockRules.forgetReleases(withoutSessionsEnding: sessions.map(\.end),
                                               since: since, in: &state)
        if !released.isEmpty || forgot { commit(reschedule: false) }
    }

    func noteInterventionShown(_ kind: InterventionKind, at now: Date = Date()) {
        BlockTrace.step("Otto's \(kind.rawValue) screen is up")
        state.recentInterventions.append(kind.rawValue)
        state.lastInterventionAt = now
        // Saved without a pass over the shields: nothing here changes what
        // is held, and that pass was one more round of Screen Time writes
        // every time Otto appeared.
        BlockRules.prune(&state, now: now)
        BlockStore.save(state)
    }

    var recentInterventions: [InterventionKind] {
        state.recentInterventions.compactMap(InterventionKind.init(rawValue:))
    }

    /// Re-reads what the extensions wrote (asks, daily limits) and puts the
    /// shields right. On every return to the foreground.
    func refresh() {
        BlockTrace.step("refresh")
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
            ScreenTimeWork.reconcileShields("808 is back")
        }
    }

    /// Asks for an Otto screen, from the notification or an unanswered ask.
    func requestIntervention() {
        BlockTrace.step("Otto requested (notification tapped)")
        interventionRequest = Date()
    }

    var hasUnansweredAsk: Bool { BlockRules.unansweredAsk(state, at: Date()) }

    /// Tapping the notification both delivers it AND brings 808 to the
    /// foreground, and each of those asks for Otto. The first one wins; the
    /// other, a moment later, would queue a second screen behind the first.
    ///
    /// **Two seconds, not fifteen** (2026-09-23). Those two asks land within
    /// a second of each other; fifteen also swallowed the next real tap, so
    /// closing Otto and tapping "Otto wants a word" again opened 808 on
    /// nothing (Melvin). A screen already up is `BlockHooks.ottoShowing`'s
    /// job, not this window's.
    private var lastPresentation: Date?

    func claimPresentation(now: Date = Date()) -> Bool {
        if let last = lastPresentation, now.timeIntervalSince(last) < 2 { return false }
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
            let saved = state
            ScreenTimeWork.run("schedules") {
                let refused = BlockSchedule.sync(saved)
                Task { @MainActor [weak self] in
                    self?.problem = refused.isEmpty ? nil
                        : "Screen Time didn't take \(refused.joined(separator: ", ")). Try saving it again."
                }
            }
        }
        ScreenTimeWork.reconcileShields(reschedule ? "blockers changed" : "state saved")
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

/// Screen Time's calls, made off the main thread (2026-10-06).
///
/// Every shield write (ManagedSettings) and schedule call (DeviceActivity) is
/// a synchronous trip to a system daemon, and the app made them on the main
/// thread: two or three rounds of shield writes each time 808 came back from
/// a held app, at the very moment the shield's "Ask Otto" had those daemons
/// busy redrawing it, plus one more as Otto appeared. A slow answer stopped
/// 808 with it, which is the likeliest reading of the fifteen seconds
/// Melvin's phone froze for on his second "Ask Otto" in a row.
///
/// Now they run here, one at a time and in the order asked, each holding a
/// background-task assertion: the moment after "Not now" is exactly when
/// somebody leaves 808 for the app it just opened, and the work must not be
/// suspended halfway. The monitor extension still calls `BlockShields`
/// directly, on its own thread.
enum ScreenTimeWork {
    private static let queue = DispatchQueue(label: "com.lockout.meditate808.block.screen-time",
                                             qos: .userInitiated)
    private static let lock = NSLock()
    /// A shield pass is queued and has not started. Read and written under
    /// `lock`, from the main thread and the queue.
    nonisolated(unsafe) private static var shieldPassWaiting = false

    @MainActor
    static func run(_ what: String, _ work: @escaping @Sendable () -> Void) {
        let hold = BackgroundHold(what)
        BlockTrace.step("queued: \(what)")
        queue.async {
            BlockTrace.timed(what, work)
            Task { @MainActor in hold.end() }
        }
    }

    /// Brings every shield in line with the saved state. A pass reads the
    /// state when it starts, so an ask that arrives while one is still
    /// waiting to run is covered by it and joins it, rather than queueing
    /// another round of the same writes.
    @MainActor
    static func reconcileShields(_ why: String) {
        lock.lock()
        let joined = shieldPassWaiting
        shieldPassWaiting = true
        lock.unlock()
        if joined {
            BlockTrace.step("shields (\(why)): joins the pass already waiting")
            return
        }
        run("shields (\(why))") {
            lock.lock()
            shieldPassWaiting = false
            lock.unlock()
            let done = BlockShields.reconcile()
            BlockTrace.step("shields: \(done.held) held, \(done.lifted) lifted")
        }
    }
}

/// Keeps 808 running in the background until a piece of Screen Time work
/// has finished, or iOS says time is up.
@MainActor
private final class BackgroundHold {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(_ name: String) {
        // iOS calls this on the main thread, and the task has to end before
        // it returns or the app is killed.
        id = UIApplication.shared.beginBackgroundTask(withName: "Block: \(name)") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
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
        let info = notification.request.content.userInfo
        if info["block"] != nil {
            BlockTrace.step("\"Otto wants a word\" arrived with 808 open")
            completionHandler([.banner, .sound])
        } else if info[SessionEndNotice.userInfoKey] != nil {
            // The sit screen is already saying it is over, and `SessionBell`
            // is ringing (it sounds on silent; this sound would not), so
            // nothing: two sounds at once would step on the bell.
            completionHandler([])
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        if request.content.userInfo["block"] != nil {
            BlockTrace.step("\"Otto wants a word\" tapped")
            Task { @MainActor in BlockController.shared.requestIntervention() }
        } else if let kind = Analytics.notificationKind(identifier: request.identifier,
                                                        userInfo: request.content.userInfo) {
            // 808's own notifications only. Block's ask is never tracked:
            // Screen Time's terms keep what Block does on the phone.
            Analytics.track(.notificationOpened(kind: kind))
        }
        completionHandler()
    }
}
