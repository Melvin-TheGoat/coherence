import Foundation

/// How 808 is sold, as one switch, so the decision can move again without a
/// re-plumb.
///
/// **Premium only (Melvin and Aziz, 2026-09-23, on a call):** "decided to make
/// this version premium only, likely with a 3 day free trial." So there is no
/// free tier while this is true: onboarding ends on the paywall, declining
/// its offers returns to it, and a person with no subscription meets it again
/// at launch (`RootView`). The free tier built on 2026-08-24
/// (`ENTITLEMENTS.md`, `FreeTierScreen`) stays in the code, unreachable.
///
/// **The app fails CLOSED (Melvin, 2026-09-29).** It used to open for
/// everyone whenever the App Store had not answered: offline, a slow sandbox,
/// or five seconds of waiting all walked a non-member into a paid app. Now an
/// onboarded person with no entitlement always meets the paywall (`LaunchLock`),
/// and a paywall that cannot load its plans says so and offers Try again,
/// Restore and the Account link. What keeps a payer out of that screen is
/// StoreKit's on-device record (`Transaction.currentEntitlements`), which
/// needs no network and is read before the plans are fetched.
enum Monetization {
    static let premiumOnly = true

    /// The free trial is back (Melvin, 2026-09-29: "same as before, 3 day
    /// offer"). The paywall's Monthly and Yearly sell with their own App
    /// Store introductory offer, and every line that states it reads the
    /// product's real offer and this person's eligibility (`Store`), so
    /// somebody who already used a trial is never promised one.
    ///
    /// It was off from 2026-09-26 (Aziz: "no free trial and only monthly and
    /// yearly"). **App Store Connect must match:** the trial IS each
    /// product's introductory offer, 3 days free on
    /// `com.lockout.meditate808.monthly` and `.yearly`. A product without one
    /// simply sells without a trial, and this screen says so.
    static let freeTrial = true

    /// The founders' side-by-side beta: the same app under a bundle ID ending
    /// in ".dev" (`tools/beta_install.sh`), which owns no products in App
    /// Store Connect, so its plans can never load. Failing closed would lock
    /// it on "Plans aren't loading" forever, so it is the one build that
    /// stays open without a membership (Melvin, 2026-09-29).
    static var isSideBySideBeta: Bool {
        isSideBySideBeta(bundleID: Bundle.main.bundleIdentifier)
    }

    static func isSideBySideBeta(bundleID: String?) -> Bool {
        bundleID?.hasSuffix(".dev") == true
    }
}

/// What the launch shows an onboarded person, decided in one pure function so
/// the fail-closed rule is tested rather than trusted (Melvin, 2026-09-29).
///
/// `RootView` asks this in Release. DEBUG builds never lock (`HARD_PAYWALL=1`
/// reviews the lock there), and a running session is never replaced by the
/// lock; both stay in `RootView`, because they are about the screen, not the
/// money.
enum LaunchLock {
    enum Verdict: Equatable {
        /// The app itself.
        case open
        /// The daytime valley with nothing on it, while the answer is due.
        case wait
        /// The paywall.
        case lock
    }

    /// - Parameters:
    ///   - entitlementKnown: StoreKit's on-device record has been read once.
    ///     It is local and quick, and until it is read a payer and a
    ///     stranger look the same, so the launch waits for it with no
    ///     timeout rather than flash a payer the paywall.
    ///   - waitExpired: the launch has waited long enough for the App Store.
    ///     **It leads to the paywall, never to the app**: the paywall in its
    ///     "Plans aren't loading" state has a Try again, and a blank valley
    ///     with no way forward is worse than that.
    static func verdict(state: Store.State, entitled: Bool, entitlementKnown: Bool,
                        waitExpired: Bool, sideBySideBeta: Bool) -> Verdict {
        guard Monetization.premiumOnly, !sideBySideBeta else { return .open }
        if entitled { return .open }
        if !entitlementKnown { return .wait }
        if state == .loading && !waitExpired { return .wait }
        // `.ready`, `.unavailable`, or a fetch that has not answered in time:
        // all of them are the paywall for somebody without a membership.
        return .lock
    }
}

/// How the free trial is said. Its length is each product's introductory
/// offer in App Store Connect, read when the products load
/// (`Store.trialDays`, `Store.freeTrialDays(for:)`), so changing the trial
/// there changes every line that states it, with no build.
enum TrialCopy {
    /// "3 days", "7 days", "1 day".
    static func length(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    /// "Three", "Seven": for a line that opens with the number.
    static func spelled(_ days: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = Locale(identifier: "en_US")
        return (f.string(from: NSNumber(value: days)) ?? "\(days)").capitalized
    }

    /// The button that starts the trial: "Start 3 days free".
    static func startButton(_ days: Int) -> String {
        "Start \(length(days)) free"
    }
}
