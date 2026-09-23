import Foundation
import SwiftUI
import Intents
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
/// The switch reports `INFocusStatusCenter`, which is the phone's real
/// state, not what was tapped last week. A switch that says silenced while a
/// banner slides over Otto is worse than no switch, so when the status is
/// unreadable (permission declined) it falls back to reporting only what we
/// ourselves turned on, and never more than that.
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
    private static let askedKey = "focus.statusAsked.v1"

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
    static let silenceInstallURL: URL? = nil
    static let restoreInstallURL: URL? = nil

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
    /// links do not exist) they made both shortcuts by hand and said so.
    ///
    /// **"Shortcut not found" was this flag lying** (Melvin, 2026-09-23). The
    /// old Add shortcut button set it on every tap, even with a nil link that
    /// opened nothing, so the next tap ran `808 Silence` on a phone that had
    /// never been given it. It is now set only by `markInstalled()`, which
    /// the sheet calls after the step that earns it, and the key moved to v2
    /// so the stale `true` is gone. Still not proof the shortcuts survive
    /// (they can be deleted), which no API can tell us.
    @Published private(set) var installed: Bool

    /// What the switch shows: on while 808's own silence is in force, or
    /// while the phone reports a Focus of the person's own.
    @Published private(set) var silenced = false

    /// When 808 switched Do Not Disturb on, while it is still 808's to put
    /// back; nil otherwise. A Focus the user switched on themselves is
    /// theirs, and 808 must not switch it off at the end of a sit.
    ///
    /// **Stored, not held in memory.** Only the foreground can open
    /// Shortcuts, so a timed sit that ends with the phone locked cannot put
    /// the phone back then, and iOS may close 808 mid-sit. Either way the
    /// phone would stay silent after the meditation with nothing left that
    /// remembered why.
    private var silencedAt: Date? {
        get { defaults.object(forKey: Self.silencedAtKey) as? Date }
        set { defaults.set(newValue, forKey: Self.silencedAtKey) }
    }
    private var weSilencedIt: Bool { silencedAt != nil }
    private static let silencedAtKey = "focus.silencedAt.v1"

    /// A restore is owed and has not run: the sit ended while 808 could not
    /// reach Shortcuts, or 808 was relaunched with its silence still on.
    /// `becameActive` pays it.
    private var restorePending = false

    /// The phone has reported a Focus on since 808 silenced it. Only then is
    /// a later "off" believed (see `focusReading`).
    private var statusConfirmedOn = false

    /// Older than this, a silence is no longer surely the one 808 made (the
    /// person may have switched it off and on again since), so it is
    /// forgotten rather than switched off.
    private static let restoreWindow: TimeInterval = 12 * 3600

    /// Focus status lags a change by a moment, in both directions. Until
    /// this passes after 808 switches the phone, what 808 just did outranks
    /// what the status says; then the status is read again (`settle`).
    private var settlingUntil: Date?
    private var settleTask: Task<Void, Never>?

    /// Whether the Focus permission dialog has already been put in front of
    /// this person. **Nothing touches `INFocusStatusCenter` until it has.**
    ///
    /// Found on the simulator: merely reading the status centre raises
    /// Apple's "Allow 808 to share that you have notifications silenced"
    /// dialog. Opening the session screen therefore threw a system prompt at
    /// somebody who was about to close their eyes, which is the single worst
    /// moment in the app to ask for anything. The read is now downstream of
    /// an explicit tap on the switch, and this flag is what keeps it there.
    private var hasAsked: Bool {
        get { defaults.bool(forKey: Self.askedKey) }
        set { defaults.set(newValue, forKey: Self.askedKey) }
    }

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

    // MARK: - Reading the phone

    /// Asks once for permission to read Focus status. Declining is fine: the
    /// switch then reports only what 808 itself did, which is less but is
    /// still true.
    func requestStatusAccess() async {
        let first = !hasAsked
        hasAsked = true
        guard first || INFocusStatusCenter.default.authorizationStatus == .notDetermined else {
            refreshStatus()
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            INFocusStatusCenter.default.requestAuthorization { _ in c.resume() }
        }
        refreshStatus()
    }

    /// Re-reads the phone. Call on appear and on returning to the foreground,
    /// because the user can change Focus from Control Center while 808 is
    /// sitting there showing a switch.
    func refreshStatus() {
        if let until = settlingUntil, Date() < until {
            silenced = weSilencedIt
            return
        }
        let reading = focusReading()
        if weSilencedIt {
            if reading == true {
                statusConfirmedOn = true
            } else if reading == false, statusConfirmedOn {
                // The phone has shown it reports this Focus, and now says it
                // is off: they turned it off themselves. Not ours to put back.
                silencedAt = nil
                statusConfirmedOn = false
                restorePending = false
            }
        }
        silenced = weSilencedIt || reading == true
    }

    /// The phone's own answer, or nil when 808 may not ask (not asked yet,
    /// or declined).
    ///
    /// **"Off" is not believed until it has said "on"** (Melvin, 2026-09-23:
    /// the switch stayed off while the shortcut really did silence the
    /// phone). It reads off for a moment while the Focus change lands, and
    /// ALWAYS reads off when Share Focus Status is turned off for Do Not
    /// Disturb (Settings, Focus, Focus Status). Taking that "off" at its word
    /// flipped the switch back and, worse, dropped the note that 808 had
    /// silenced the phone, so nothing switched Do Not Disturb off when the
    /// sit ended. What 808 did itself is known for certain; the status only
    /// ever adds to it.
    private func focusReading() -> Bool? {
        guard hasAsked, INFocusStatusCenter.default.authorizationStatus == .authorized
        else { return nil }
        return INFocusStatusCenter.default.focusStatus.isFocused
    }

    /// Called whenever 808 comes to the foreground (`CoherenceApp`), and once
    /// at launch. Pays a restore that was owed while 808 could not reach
    /// Shortcuts, then re-reads the phone.
    func becameActive() async {
        if restorePending { await restoreIfOurs() }
        refreshStatus()
    }

    // MARK: - Turning it on and off

    /// Runs the silence shortcut. Returns false when Shortcuts could not be
    /// opened. Nothing reports whether the shortcut itself then ran, which is
    /// why the switch is set from what 808 did rather than from the phone.
    @discardableResult
    func silence() async -> Bool {
        guard installed else { return false }
        guard await run(Self.silenceName) else { return false }
        silencedAt = Date()
        statusConfirmedOn = false
        restorePending = false
        silenced = true
        settle()
        return true
    }

    /// The switch tapped off. An explicit ask, so it runs whether or not 808
    /// switched the Focus on; only the end of a sit is held to
    /// `restoreIfOurs`. Restore switches Do Not Disturb off and nothing else,
    /// so another Focus they have on (Sleep, Work) stays on, and the switch
    /// says so once the status settles.
    func turnOff() async {
        guard installed, await run(Self.restoreName) else { return }
        forget()
        settle()
    }

    /// Puts the phone back, but only if 808 is the one that silenced it.
    ///
    /// Called at the end of every sit. The guard is the point: somebody who
    /// meditates inside their own Sleep focus must not come out of a session
    /// with their phone unsilenced at eleven at night.
    func restoreIfOurs() async {
        guard let since = silencedAt, installed else { return }
        guard Date().timeIntervalSince(since) < Self.restoreWindow,
              UIApplication.shared.canOpenURL(URL(string: "shortcuts://")!)
        else {
            forget()
            return
        }
        // Only the foreground can open Shortcuts. A timed sit that ends with
        // the phone locked restores the next time 808 comes forward, rather
        // than leaving the phone silent.
        guard UIApplication.shared.applicationState == .active,
              await run(Self.restoreName)
        else {
            restorePending = true
            return
        }
        forget()
        settle()
    }

    private func forget() {
        silencedAt = nil
        statusConfirmedOn = false
        restorePending = false
        silenced = false
    }

    /// Starts the window in which 808's own action decides the switch, and
    /// reads the phone again when it closes.
    private func settle() {
        let window: TimeInterval = 4
        settlingUntil = Date().addingTimeInterval(window)
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window + 0.3))
            // A cancelled sleep throws and falls through: never act on it.
            guard !Task.isCancelled else { return }
            self?.refreshStatus()
        }
    }

    private func run(_ name: String) async -> Bool {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "shortcuts://x-callback-url/run-shortcut?name=\(encoded)&x-success=coherence808://focus")
        else { return false }
        guard UIApplication.shared.canOpenURL(URL(string: "shortcuts://")!) else {
            log.error("Shortcuts is not installed on this phone")
            return false
        }
        let opened = await UIApplication.shared.open(url)
        if !opened { log.error("could not run the shortcut \(name)") }
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
