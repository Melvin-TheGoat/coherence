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
    /// they are filled in, `isConfigured` is false and the screen shows its
    /// Control Center line instead, so the build never offers a switch that
    /// cannot work.
    ///
    /// Each shortcut is one action: Set Focus, Do Not Disturb, On (or Off).
    static let silenceInstallURL: URL? = nil
    static let restoreInstallURL: URL? = nil

    /// Whether the feature can work at all on this build.
    static var isConfigured: Bool {
        #if DEBUG
        return true          // so the flow can be walked before the links exist
        #else
        return silenceInstallURL != nil && restoreInstallURL != nil
        #endif
    }

    /// The user has been through the setup. Not proof the shortcuts survived
    /// (they can be deleted), which is why `silence()` checks the outcome.
    @Published private(set) var installed: Bool

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
        self.installed = defaults.bool(forKey: Self.installedKey)
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

    /// Opens the iCloud link so Shortcuts can offer to add it.
    func openInstall(_ url: URL?) async {
        guard let url else { return }
        _ = await UIApplication.shared.open(url)
    }
}
