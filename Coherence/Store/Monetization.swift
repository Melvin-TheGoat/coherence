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
/// **Nobody is locked out by a failure.** The lock engages only once the App
/// Store has actually returned the plans (`Store.State.ready`). Offline, or
/// before the products exist, the app stays open: the rule the first hard
/// paywall kept (2026-08-11), and the one that keeps an App Review device
/// whose sandbox products are slow from being stuck on a screen that cannot
/// sell anything.
enum Monetization {
    static let premiumOnly = true

    /// No free trial (Aziz, 2026-09-26: "no free trial and only monthly and
    /// yearly"). While false, no screen offers or mentions a trial: the
    /// paywall sells the plans outright, the ladder opens on half off the
    /// first year, and the lock sheets say "See the plans".
    ///
    /// **App Store Connect must match.** The trial itself is the monthly
    /// product's introductory offer; while that offer exists, Apple's
    /// purchase sheet still grants it whatever this screen says. Delete the
    /// introductory offer on `com.lockout.meditate808.monthly` (and yearly,
    /// if it has one) before a build with this switch ships.
    static let freeTrial = false
}

/// How the free trial is said. Its length is the monthly product's
/// introductory offer in App Store Connect, read when the products load
/// (`Store.trialDays`), so changing the trial there changes every line that
/// states it, with no build.
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
