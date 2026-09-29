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

    /// Whether the paywall's OWN Monthly and Yearly sell with a free trial.
    /// **Off: the free trial is an upsell** (Melvin, 2026-09-29: "we want them
    /// to not know it exists unless they deny the initial offer"). The paywall
    /// sells Monthly, Yearly and Lifetime with no trial; "No, I don't want to
    /// pay" offers the 3-day free trial (`...monthlytrial`), and declining that
    /// offers half price after a 3-day trial (`...monthly50`). Each rung's
    /// trial is its own product's introductory offer.
    ///
    /// For a few hours that day it was on, a misreading of "same as before, 3
    /// day offer": the trial sat on the paywall and the trial rung went
    /// dormant. **App Store Connect must match:** `monthly` and `yearly` carry
    /// NO introductory offer, or Apple's purchase sheet grants a trial this
    /// screen never mentions (the 3.1.2 mismatch) and the upsell is gone.
    static let freeTrial = false

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
