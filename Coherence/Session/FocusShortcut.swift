import Foundation
import SwiftUI
import os

/// Silencing the phone for the length of a sit, and only for the length of a
/// sit.
///
/// ## What iOS allows, exactly
///
/// **No app can switch Do Not Disturb on.** There is no API for it, and the
/// private `App-prefs:` URLs that appear in blog posts are a rejection. The
/// one thing Apple does let switch Focus is **Shortcuts**, and Shortcuts can
/// be driven from another app by its public `shortcuts://` scheme. So the
/// mechanism is: the user installs two tiny shortcuts once, from signed
/// iCloud links (two taps, no "Allow Untrusted Shortcuts" detour), and from
/// then on 808 runs them by name.
///
/// `x-callback-url` carries `x-success`, so the bounce out to Shortcuts
/// returns here by itself. It is about half a second and it is visible; there
/// is no way to make it invisible, and pretending otherwise would be the kind
/// of claim this product does not make.
///
/// **Only the callback is proof** (App Review pass, 2026-09-29). The switch
/// used to count the phone silenced the moment `UIApplication.open` handed
/// the URL to Shortcuts, and nothing listened for the answer, so a missing or
/// failed shortcut still read "on" and 808 believed Do Not Disturb was on.
/// Now every run carries `x-success`, `x-error` and `x-cancel`, each naming
/// the action and the moment it was asked (`handle`, wired to `.onOpenURL`
/// in `CoherenceApp`). Only `x-success` records anything. The switch flips
/// on while Shortcuts runs, and falls back to what was proven when no
/// answer comes back within a few seconds of returning (`armAnswerCheck`).
///
/// ## Only for the meditation
///
/// Aziz's constraint, and it is the whole reason this is two shortcuts rather
/// than one toggle. Silence goes on when the switch is flipped and comes off
/// when the sit ends, whether it ended at the timer, at End, or because the
/// screen was left. A toggle would drift out of step the first time somebody
/// changed Focus by hand; naming the two directions cannot.
///
/// ## Honesty
///
/// The switch shows what 808 did and Shortcuts confirmed, and nothing more.
/// It used to read `INFocusStatusCenter` as well, which put a Focus status
/// permission prompt in front of people. That API is meant for communication
/// apps, and App Review asks what a meditation app wants with it, so it is
/// gone (App Review pass, 2026-09-29), along with the settle window that
/// existed only because the status lagged a change.
@MainActor
final class FocusShortcut: ObservableObject {
    static let shared = FocusShortcut()

    private let log = Logger(subsystem: "com.lockout.meditate808", category: "FocusShortcut")
    private let defaults: UserDefaults
    /// v2 since 2026-09-23: the v1 build saved `true` from an "Add shortcut"
    /// tap that installed nothing (the links were still nil), and every phone
    /// that tapped it would go on trying to run a shortcut that is not there.
    /// A new key starts everyone from "not set up", which is the truth.
    private static let installedKey = "focus.shortcutsInstalled.v2"

    /// The names the two shortcuts must carry. They are what `run-shortcut`
    /// looks up, so they are part of the contract with the installed
    /// shortcut and cannot be changed without republishing both links.
    static let silenceName = "808 Silence"
    static let restoreName = "808 Restore"

    /// The signed iCloud links the two shortcuts are installed from.
    ///
    /// **These are empty until somebody with the Apple ID publishes them.**
    /// Making a shortcut and sharing it to iCloud is a human step in the
    /// Shortcuts app; there is no way to generate the link from here. Until
    /// they are filled in, Release shows the Control Center line instead of
    /// the switch, and a DEBUG build's setup sheet walks through making the
    /// two by hand (which is also how the links get made).
    ///
    /// **What to create, exactly (two shortcuts, in the Shortcuts app):**
    /// 1. Name it **`808 Silence`** (must match `silenceName` exactly, since
    ///    that is the string `run-shortcut?name=` looks up). One action:
    ///    Set Focus > Do Not Disturb > Turn On.
    /// 2. Name it **`808 Restore`** (must match `restoreName`). One action:
    ///    Set Focus > Do Not Disturb > Turn Off.
    /// 3. Share each one (the ••• menu > Share > Copy iCloud Link) and paste
    ///    the two resulting `https://www.icloud.com/shortcuts/...` links in
    ///    below, one per constant. Nothing else in the app needs to change:
    ///    the setup sheet switches to its two-tap install, and Release starts
    ///    drawing the switch.
    ///
    /// Published by Melvin, 2026-09-25, and checked against iCloud before
    /// they went in: the names match `silenceName` / `restoreName` exactly,
    /// and each holds one action, Do Not Disturb on (Silence) or off
    /// (Restore).
    static let silenceInstallURL: URL? = URL(string: "https://www.icloud.com/shortcuts/79d5372830ec4678968d2b0db130bc9f")
    static let restoreInstallURL: URL? = URL(string: "https://www.icloud.com/shortcuts/c7e4855d192a47e9991c8e9a71558601")

    /// Both links exist, so setup is two taps rather than making the
    /// shortcuts by hand.
    static var hasInstallLinks: Bool {
        silenceInstallURL != nil && restoreInstallURL != nil
    }

    /// Whether the switch is drawn at all. Release waits for the links;
    /// DEBUG draws it now, and its setup sheet has the by-hand path.
    static var isConfigured: Bool {
        #if DEBUG
        return true
        #else
        return hasInstallLinks
        #endif
    }

    /// The person has been through setup: both links opened, or (while the
    /// links do not exist) they made both shortcuts by hand and said so, or
    /// a shortcut has answered `x-success`.
    ///
    /// **"Shortcut not found" was this flag lying** (Melvin, 2026-09-23). The
    /// old Add shortcut button set it on every tap, even with a nil link that
    /// opened nothing, so the next tap ran `808 Silence` on a phone that had
    /// never been given it. It is now set only by `markInstalled()`, which
    /// the sheet calls after the step that earns it, and the key moved to v2
    /// so the stale `true` is gone.
    ///
    /// **Opening a link is still not proof** (App Review pass, 2026-09-29):
    /// the person can open it and never tap Add. So an `x-error` from either
    /// shortcut takes the flag back and reopens the setup steps
    /// (`setupNeeded`), and an `x-success` sets it for good.
    @Published private(set) var installed: Bool

    /// What the switch shows: on while 808's own silence is in force, and
    /// for the few seconds a Silence run is out in Shortcuts.
    @Published private(set) var silenced = false

    /// A shortcut came back with an error, which almost always means it is
    /// not on this phone. The Ready screen watches this and reopens the
    /// setup steps (`setupShown()` clears it).
    @Published private(set) var setupNeeded = false

    /// Do Not Disturb that 808 turned on is still owed back and 808 has come
    /// to the foreground: the root asks, once, with a one-tap alert
    /// (`FocusRestorePrompt`).
    ///
    /// **It asks; it never jumps** (App Review pass, 2026-09-29). This used
    /// to open Shortcuts by itself at launch and on every return, which threw
    /// the person into another app without a tap.
    @Published var restorePrompt = false
    /// "808 Restore" answered x-error: Do Not Disturb is still on and 808
    /// can't turn it off. Said once, with where to do it (2026-09-30); it
    /// used to forget the silence and say nothing.
    @Published var restoreFailed = false

    /// When 808 switched Do Not Disturb on, while it is still 808's to put
    /// back; nil otherwise. A Focus the user switched on themselves is
    /// theirs, and 808 must not switch it off at the end of a sit.
    ///
    /// **Stored, not held in memory.** Only the foreground can open
    /// Shortcuts, so a timed sit that ends with the phone locked cannot put
    /// the phone back then, and iOS may close 808 mid-sit. Either way the
    /// phone would stay silent after the meditation with nothing left that
    /// remembered why.
    ///
    /// Set only by an `x-success` from `808 Silence` (App Review pass,
    /// 2026-09-29), never by the tap that asked for it.
    private var silencedAt: Date? {
        get { defaults.object(forKey: Self.silencedAtKey) as? Date }
        set { defaults.set(newValue, forKey: Self.silencedAtKey) }
    }
    private var weSilencedIt: Bool { silencedAt != nil }
    private static let silencedAtKey = "focus.silencedAt.v1"

    /// A restore is owed and has not run: the sit ended while 808 could not
    /// reach Shortcuts, or 808 was relaunched with its silence still on.
    /// `becameActive` asks about it (`restorePrompt`).
    private var restorePending = false

    /// Older than this, a silence is no longer surely the one 808 made (the
    /// person may have switched it off and on again since), so it is
    /// forgotten rather than switched off.
    private static let restoreWindow: TimeInterval = 12 * 3600

    /// The two shortcuts, as they appear in the callback URLs.
    enum Action: String { case silence, restore }
    /// Which of the three x-callback URLs Shortcuts opened.
    enum Outcome: String { case success, error, cancel }

    /// The run that is out in Shortcuts and has not answered yet. `stamp` is
    /// the milliseconds it was asked at, carried in its callback URLs, so an
    /// answer is matched to the run that asked for it.
    private var awaiting: (action: Action, stamp: Int)?
    private var answerCheck: Task<Void, Never>?

    /// How long after returning to 808 an answer may still arrive before the
    /// run counts as unanswered. The callback lands within a second of the
    /// return; this leaves room for a slow phone.
    private static let answerGrace: TimeInterval = 3

    /// An `x-success` older than this is not acted on: it belongs to a run
    /// nobody is waiting for any more.
    private static let lateAnswer: TimeInterval = 120

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.installed = defaults.bool(forKey: Self.installedKey)
        // A silence still on the books at launch belongs to a sit that ended
        // with the last process: nothing can be running yet. The restore is
        // owed.
        restorePending = weSilencedIt
        silenced = weSilencedIt
    }

    func markInstalled() {
        defaults.set(true, forKey: Self.installedKey)
        installed = true
    }

    private func markNotInstalled() {
        defaults.set(false, forKey: Self.installedKey)
        installed = false
    }

    /// The Ready screen has put the setup steps up for `setupNeeded`.
    func setupShown() { setupNeeded = false }

    /// Called whenever 808 comes to the foreground (`CoherenceApp`), and once
    /// at launch. Waits a moment for the answer to a run that went out to
    /// Shortcuts, and raises the one-tap prompt for a restore that was owed
    /// while 808 could not reach Shortcuts.
    func becameActive() async {
        if let run = awaiting { armAnswerCheck(for: run.stamp) }
        guard restorePending, !restorePrompt else { return }
        guard let since = silencedAt, installed,
              Date().timeIntervalSince(since) < Self.restoreWindow
        else {
            forget()
            return
        }
        promptTask?.cancel()
        promptTask = Task { [weak self] in await self?.raisePromptWhenClear() }
    }

    private var promptTask: Task<Void, Never>?
    private var failureTask: Task<Void, Never>?

    /// Raises `restoreFailed` once nothing is presented over the root (the
    /// reward screen closed), however long that takes while 808 is open.
    private func raiseFailureWhenClear() async {
        try? await Task.sleep(for: .seconds(2))
        while !Task.isCancelled {
            if UIApplication.shared.applicationState == .active,
               !restorePrompt, !Self.somethingPresented() {
                restoreFailed = true
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Raises `restorePrompt` once 808 has settled and nothing else is on
    /// screen over Home.
    ///
    /// Found on the simulator: an alert raised in the same moment as the
    /// launch, or while one of ContentView's covers is up or on its way,
    /// wins, and the cover never opens (the Ready screen, and it would be the
    /// reward or Otto's screen just the same). So it waits two seconds, then
    /// for the screen to be clear of covers, and asks then. Leaving 808
    /// cancels the wait; the next return starts it again.
    private func raisePromptWhenClear() async {
        try? await Task.sleep(for: .seconds(2))
        while !Task.isCancelled {
            guard restorePending, !restorePrompt,
                  UIApplication.shared.applicationState == .active
            else { return }
            if !Self.somethingPresented() {
                restorePrompt = true
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Whether any cover or sheet is up over the root.
    private static func somethingPresented() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        return root?.presentedViewController != nil
    }

    /// "Turn it off" on the prompt.
    func acceptRestorePrompt() async {
        restorePrompt = false
        restorePending = false
        await restoreIfOurs()
    }

    /// "Keep it on" on the prompt: the silence is theirs now, and 808 stops
    /// owing it back.
    func declineRestorePrompt() {
        restorePrompt = false
        forget()
    }

    // MARK: - Turning it on and off

    /// Runs the silence shortcut. Returns false when Shortcuts could not be
    /// opened. The switch reads on while the shortcut runs, but 808 only
    /// records the silence when `808 Silence` answers `x-success`.
    @discardableResult
    func silence() async -> Bool {
        guard installed else { return false }
        setupNeeded = false
        silenced = true
        guard await run(.silence) else {
            silenced = weSilencedIt
            return false
        }
        return true
    }

    /// The switch tapped off. The switch only ever reads on for 808's own
    /// silence, so this is always putting back what 808 did. Restore switches
    /// Do Not Disturb off and nothing else, so another Focus they have on
    /// (Sleep, Work) stays on.
    func turnOff() async {
        guard installed else { return }
        silenced = false
        guard await run(.restore) else {
            silenced = weSilencedIt
            return
        }
    }

    /// Puts the phone back, but only if 808 is the one that silenced it.
    ///
    /// Called at the end of every sit, from several places for the same
    /// ending, so a Restore already out in Shortcuts is not sent twice. The
    /// guard is the point: somebody who meditates inside their own Sleep
    /// focus must not come out of a session with their phone unsilenced at
    /// eleven at night.
    func restoreIfOurs() async {
        guard let since = silencedAt, installed else { return }
        guard awaiting?.action != .restore else { return }
        guard Date().timeIntervalSince(since) < Self.restoreWindow,
              UIApplication.shared.canOpenURL(URL(string: "shortcuts://")!)
        else {
            forget()
            return
        }
        // Only the foreground can open Shortcuts. A timed sit that ends with
        // the phone locked is asked about the next time 808 comes forward
        // (`restorePrompt`), rather than leaving the phone silent.
        guard UIApplication.shared.applicationState == .active else {
            restorePending = true
            return
        }
        silenced = false
        guard await run(.restore) else {
            restorePending = true
            silenced = weSilencedIt
            return
        }
    }

    private func forget() {
        silencedAt = nil
        restorePending = false
        silenced = false
    }

    // MARK: - The answer from Shortcuts

    /// Handles `coherence808://focus/<action>/<stamp>/<outcome>`, the three
    /// x-callback URLs `run` hands to Shortcuts. Returns false for any other
    /// URL, so it can sit in a shared `.onOpenURL`.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "coherence808", url.host == "focus" else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3,
              let action = Action(rawValue: parts[0]),
              let stamp = Int(parts[1]),
              let outcome = Outcome(rawValue: parts[2])
        else { return true }
        let asked = Date(timeIntervalSince1970: Double(stamp) / 1000)
        let isCurrent = awaiting?.action == action && awaiting?.stamp == stamp
        if isCurrent {
            awaiting = nil
            answerCheck?.cancel()
        }
        log.info("\(action.rawValue) answered \(outcome.rawValue)")

        switch (action, outcome) {
        case (.silence, .success):
            guard Date().timeIntervalSince(asked) < Self.lateAnswer else { return true }
            markInstalled()
            silencedAt = asked
            restorePending = false
            silenced = true
        case (.restore, .success):
            markInstalled()
            // Only a restore asked for after the current silence clears it.
            if let since = silencedAt, asked >= since { forget() } else { silenced = weSilencedIt }
        case (_, .error):
            // Almost always "no shortcut by that name". Take the setup flag
            // back and show the steps again, quietly.
            guard isCurrent else { return true }
            markNotInstalled()
            if action == .restore {
                forget()
                // Not raised at once: this answer lands as a session ends,
                // the moment the reward cover opens, and a root alert raised
                // then can stop the cover ever opening (2026-09-30). It waits
                // for a clear screen, as the restore prompt does.
                failureTask?.cancel()
                failureTask = Task { [weak self] in await self?.raiseFailureWhenClear() }
            }
            silenced = weSilencedIt
            setupNeeded = true
        case (_, .cancel):
            guard isCurrent else { return true }
            silenced = weSilencedIt
        }
        return true
    }

    /// Back in 808 with a run still unanswered: give the callback a moment
    /// to land, then show only what was proven. A Silence that never
    /// answered reads off; a Restore that never answered leaves 808's
    /// silence on the books, so the next sit's end (or the next launch)
    /// offers to put it back again.
    private func armAnswerCheck(for stamp: Int) {
        answerCheck?.cancel()
        answerCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.answerGrace))
            // A cancelled sleep throws and falls through: never act on it.
            guard !Task.isCancelled, let self,
                  self.awaiting?.stamp == stamp,
                  UIApplication.shared.applicationState == .active
            else { return }
            let unanswered = self.awaiting?.action.rawValue ?? ""
            self.log.info("\(unanswered) got no answer")
            self.awaiting = nil
            self.silenced = self.weSilencedIt
        }
    }

    private func run(_ action: Action) async -> Bool {
        guard UIApplication.shared.canOpenURL(URL(string: "shortcuts://")!) else {
            log.error("Shortcuts is not installed on this phone")
            return false
        }
        let name = action == .silence ? Self.silenceName : Self.restoreName
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        func callback(_ outcome: Outcome) -> URLQueryItem {
            URLQueryItem(name: "x-\(outcome.rawValue)",
                         value: "coherence808://focus/\(action.rawValue)/\(stamp)/\(outcome.rawValue)")
        }
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name),
                                 callback(.success), callback(.error), callback(.cancel)]
        guard let url = components.url else { return false }
        awaiting = (action, stamp)
        answerCheck?.cancel()
        let opened = await UIApplication.shared.open(url)
        if !opened {
            log.error("could not run the shortcut \(name)")
            awaiting = nil
        }
        return opened
    }

    /// Opens the iCloud link so Shortcuts can offer to add it. Returns
    /// whether it actually opened anything, so a nil (unconfigured) link is
    /// reported honestly rather than treated as a completed step.
    @discardableResult
    func openInstall(_ url: URL?) async -> Bool {
        guard let url else { return false }
        return await UIApplication.shared.open(url)
    }
}

/// The one-tap question for Do Not Disturb that 808 still owes back
/// (App Review pass, 2026-09-29). Applied once, at the root, in
/// `CoherenceApp`. An `.alert`, never a sheet: it must not compete with the
/// covers ContentView presents.
struct FocusRestorePrompt: ViewModifier {
    @ObservedObject private var focus = FocusShortcut.shared

    func body(content: Content) -> some View {
        content.alert("Do Not Disturb from your session",
                      isPresented: Binding(get: { focus.restorePrompt },
                                           set: { if !$0 { focus.restorePrompt = false } })) {
            Button("Turn it off") { Task { await focus.acceptRestorePrompt() } }
            Button("Keep it on", role: .cancel) { focus.declineRestorePrompt() }
        } message: {
            Text("808 turned on Do Not Disturb for your last session. Turn it off now?")
        }
        .alert("Do Not Disturb is still on",
               isPresented: Binding(get: { focus.restoreFailed && !focus.restorePrompt },
                                    set: { if !$0 { focus.restoreFailed = false } })) {
            Button("OK", role: .cancel) { focus.restoreFailed = false }
        } message: {
            Text("808 couldn't find the \"808 Restore\" shortcut. Turn Do Not Disturb off in Control Center, and add the shortcut again from the Silence notifications switch.")
        }
    }
}
