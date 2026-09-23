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
    private static let installedKey = "focus.shortcutsInstalled.v1"
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
    /// they are filled in, `installed` can never become true (see below), so
    /// the switch always routes to setup instead of attempting a shortcut
    /// that cannot exist.
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
    ///    `installed` (below) starts working the moment both are non-nil.
    static let silenceInstallURL: URL? = nil
    static let restoreInstallURL: URL? = nil

    /// Whether the SWITCH can be shown at all on this build — not whether it
    /// can actually run a shortcut yet, which `installed` below decides.
    /// Forced true in DEBUG so the switch's look can be previewed and sized
    /// before the two links exist; safe to force, because `installed` (the
    /// thing that gates ever calling `run-shortcut`) does not trust this and
    /// checks the real links itself.
    static var isConfigured: Bool {
        #if DEBUG
        return true
        #else
        return silenceInstallURL != nil && restoreInstallURL != nil
        #endif
    }

    /// The setup screen was completed, as last persisted. Advisory only —
    /// see `installed` below, which is what the rest of the app must read.
    @Published private var rawInstalled: Bool

    /// The user has been through setup AND the setup was for shortcuts that
    /// can actually exist.
    ///
    /// **Why this is derived rather than the stored flag itself (the bug
    /// behind "shortcut not found"):** `isConfigured` forces itself true in
    /// DEBUG so the switch can be previewed before the two iCloud links
    /// exist, and the old "Add shortcut" button called `markInstalled()`
    /// unconditionally, even when `openInstall` had nothing to open (a nil
    /// URL). That left `rawInstalled = true` saved in UserDefaults with no
    /// shortcut behind it, so the next tap skipped straight to `run()`,
    /// which built `shortcuts://x-callback-url/run-shortcut?name=808%20
    /// Silence...` for a shortcut nobody had installed — the exact "Shortcut
    /// not found" iOS reports. Requiring both links here means a stale
    /// `true` left over from that build reads as false again the moment
    /// this ships, with no reinstall needed, and a future bug in the setup
    /// path can never again mark this true without a real shortcut to run.
    var installed: Bool {
        rawInstalled && Self.silenceInstallURL != nil && Self.restoreInstallURL != nil
    }

    /// What we believe about the phone right now. Read from iOS where it is
    /// allowed, otherwise only what this app turned on.
    @Published private(set) var silenced = false

    /// True while 808 is responsible for the silence, so it knows to put the
    /// phone back. A Focus the user switched on themselves is theirs, and
    /// 808 must not switch it off at the end of a sit.
    private var weSilencedIt = false

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
        self.rawInstalled = defaults.bool(forKey: Self.installedKey)
    }

    func markInstalled() {
        defaults.set(true, forKey: Self.installedKey)
        rawInstalled = true
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
        // Before the user has been asked, 808 reports only what 808 did. That
        // is less than the truth but never more than it, and it costs nobody
        // a dialog they did not go looking for.
        guard hasAsked else {
            silenced = weSilencedIt
            return
        }
        guard INFocusStatusCenter.default.authorizationStatus == .authorized,
              let focused = INFocusStatusCenter.default.focusStatus.isFocused else {
            silenced = weSilencedIt
            return
        }
        silenced = focused
        // They turned their own Focus off mid-screen. It is no longer ours to
        // put back.
        if !focused { weSilencedIt = false }
    }

    // MARK: - Turning it on and off

    /// Runs the silence shortcut. Returns false when nothing happened, which
    /// is how a deleted shortcut is found out: there is no API to ask whether
    /// one is installed, so the outcome is the only evidence.
    @discardableResult
    func silence() async -> Bool {
        guard installed else { return false }
        guard await run(Self.silenceName) else { return false }
        weSilencedIt = true
        silenced = true
        // Focus status lags the switch by a moment; ask again once it has
        // had time to settle rather than trusting our own optimism forever.
        try? await Task.sleep(for: .milliseconds(700))
        refreshStatus()
        return silenced
    }

    /// Puts the phone back, but only if 808 is the one that silenced it.
    ///
    /// Called at the end of every sit. The guard is the point: somebody who
    /// meditates inside their own Sleep focus must not come out of a session
    /// with their phone unsilenced at eleven at night.
    func restoreIfOurs() async {
        guard weSilencedIt, installed else { return }
        weSilencedIt = false
        _ = await run(Self.restoreName)
        silenced = false
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
