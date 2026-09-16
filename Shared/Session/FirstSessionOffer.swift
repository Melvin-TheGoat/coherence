import Foundation
import Combine

/// The paywall comes AFTER the first meditation (Melvin, 2026-09-15). The
/// first session's results open fully unlocked: score, verdict, every curve
/// and reading. Leaving that screen opens the paywall. Once the paywall has
/// been shown, the free tier applies everywhere, including that first session
/// when they come back to it.
///
/// One flag on the device, not a synced field: a reinstall gets its first
/// session unlocked again, which is generous rather than wrong, and it keeps
/// the CloudKit schema out of a monetisation change. `covers` is the grant,
/// `due` is the request to present, `markShown` closes both.
@MainActor
public final class FirstSessionOffer: ObservableObject {
    public static let shared = FirstSessionOffer(defaults: .standard)

    static let shownKey = "paywall.firstSessionShown.v1"

    /// True once the post-session paywall has been presented. Read from
    /// defaults on every access so two instances (app and tests) never disagree.
    @Published public private(set) var shown: Bool
    /// The results screen for a covered session was left; the app should
    /// present the paywall now. Cleared by `markShown`.
    @Published public var due = false

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.shown = defaults.bool(forKey: Self.shownKey)
    }

    /// Whether the results screen should open unlocked for a free user.
    public var covers: Bool { !shown }

    /// Called when a covered results screen is dismissed by a free user.
    public func requestPaywall() {
        guard covers else { return }
        due = true
    }

    /// The paywall has been presented (bought or not): the grant ends.
    public func markShown() {
        defaults.set(true, forKey: Self.shownKey)
        shown = true
        due = false
    }
}

/// Onboarding ends on the Watch screen with Begin (2026-09-15: no practice
/// sit, no demo results). The app's first Home then opens the setup sheet so
/// the tap they just made lands on a real Begin.
public enum OnboardingHandoff {
    static let key = "onboarding.openSetupOnArrival.v1"

    public static func requestSetup(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }

    /// Reads and clears the request in one step.
    public static func takeSetupRequest(_ defaults: UserDefaults = .standard) -> Bool {
        let wanted = defaults.bool(forKey: key)
        if wanted { defaults.removeObject(forKey: key) }
        return wanted
    }
}
