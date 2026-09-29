import XCTest
@testable import Coherence

/// The free tier decides what every screen shows, so its one rule is asserted
/// rather than trusted to review.
final class EntitlementsTests: XCTestCase {

    /// **Unavailable is free.** Until 2026-09-12 any state but `.ready`
    /// unlocked everyone, which kept the pre-billing beta open; with products
    /// live it meant airplane mode at launch handed out the curves. A payer
    /// never needed it: their entitlement is read from StoreKit's on-device
    /// cache before products are fetched.
    func test_unavailableIsFreeForTheUnentitled() {
        XCTAssertFalse(Entitlements.resolve(state: .unavailable, entitled: false).paid,
                       "no network must not mean premium")
    }

    /// **No store state grants anything** (Melvin, 2026-09-29: fail closed).
    /// `.loading` used to be a one-fetch grace so a payer's cached
    /// entitlement could resolve before any lock drew; the launch now waits
    /// on that record itself (`LaunchLock`), so the grace only ever opened
    /// the evidence to strangers for the length of a slow fetch.
    func test_noStoreStateGrantsAnything() {
        for state in [Store.State.loading, .ready, .unavailable] {
            XCTAssertFalse(Entitlements.resolve(state: state, entitled: false).paid,
                           "\(state) must not stand in for a membership")
        }
    }

    /// A payer is paid in every state: online, offline, products or none.
    func test_entitledIsPaidEverywhere() {
        for state in [Store.State.loading, .ready, .unavailable] {
            XCTAssertTrue(Entitlements.resolve(state: state, entitled: true).paid,
                          "\(state) must never lock out a payer")
        }
    }

    /// The only combination that is actually free: the store is selling and
    /// this person has not bought.
    func test_onlySellingAndUnentitledIsFree() {
        let free = Entitlements.resolve(state: .ready, entitled: false)
        XCTAssertFalse(free.paid)
        XCTAssertFalse(free.curves)
        XCTAssertFalse(free.metrics)
        XCTAssertFalse(free.guidedTrack)
        XCTAssertFalse(free.shareCurves)

        XCTAssertTrue(Entitlements.resolve(state: .ready, entitled: true).paid)
    }

    /// Sharing is never locked, and one skin always works. The share loop is
    /// the only organic acquisition 808 has, so a free user must always have a
    /// card they can actually post.
    func test_freeAlwaysHasACardToPost() {
        let free = Entitlements.resolve(state: .ready, entitled: false)
        XCTAssertTrue(free.canUse(.midnight))
        XCTAssertFalse(free.canUse(.ember))
        XCTAssertTrue(CardSkin.free == .midnight)
    }
}

/// The share card is the one place a locked measurement can escape the app
/// entirely, as an image, to anywhere.
///
/// **Found in review, 2026-08-24 (Aziz):** the first build offered the locked
/// layouts in the pager behind a 55% black scrim as an upsell. `.receipt`
/// prints Heart, Stillness and Breath as rows, and a translucent overlay is not
/// a lock, it is a slightly dimmed readout. Every number the results screen was
/// withholding was legible and screenshottable.
///
/// The rule that came out of it, which is worth applying anywhere else a lock
/// gets built: **a lock drawn ON TOP of data is not a lock.** The only version
/// that holds is not giving the view the data.
final class ShareCardLeakTests: XCTestCase {

    private func data(withEvidence: Bool) -> ShareCardData {
        ShareCardData(
            date: Date(), durationSec: 600, bellyBreathing: false,
            overallScore: 0.81,
            stillnessScore: withEvidence ? 0.92 : nil,
            hrDecline: withEvidence ? 11 : nil,
            meanBreathingRate: withEvidence ? 5.8 : nil,
            curves: [],
            streakDays: 12,
            verdict: "Heart settled, body went almost fully still.",
            rating: nil, note: "",
            techniqueLabel: nil, soundLabel: "Silence")
    }

    /// A free user is offered exactly one card, and it is not one that draws
    /// curves or metric values.
    func test_freeIsOfferedOnlyASafeCard() {
        let styles = ShareCardStyle.free(for: data(withEvidence: false))
        XCTAssertEqual(styles.count, 1)
        XCTAssertFalse(styles.contains(.full), ".full draws the curves")
        XCTAssertFalse(styles.contains(.receipt), ".receipt prints the measurements")
    }

    /// Sharing is never blocked: there is always a card to post, or the only
    /// organic acquisition loop 808 has would close for free users.
    func test_freeAlwaysHasSomethingToPost() {
        XCTAssertFalse(ShareCardStyle.free(for: data(withEvidence: false)).isEmpty)
        XCTAssertFalse(ShareCardStyle.free(for: data(withEvidence: true)).isEmpty)
    }

    /// A paid user keeps everything.
    func test_paidKeepsEveryCard() {
        let all = ShareCardStyle.available(for: data(withEvidence: true))
        XCTAssertTrue(all.contains(.full))
        XCTAssertTrue(all.contains(.receipt))
    }
}

/// The launch fails CLOSED (Melvin, 2026-09-29: "The app must NEVER open free
/// because the App Store could not load"). `RootView` asks `LaunchLock` in
/// Release, so the whole rule is pinned here.
final class LaunchLockTests: XCTestCase {

    private func verdict(_ state: Store.State, entitled: Bool = false, known: Bool = true,
                         expired: Bool = false, beta: Bool = false) -> LaunchLock.Verdict {
        LaunchLock.verdict(state: state, entitled: entitled, entitlementKnown: known,
                           waitExpired: expired, sideBySideBeta: beta)
    }

    /// Offline, a sandbox that did not answer, or a store that is selling:
    /// all of them are the paywall for somebody without a membership.
    func test_aStoreThatAnsweredLocksTheUnentitled() {
        XCTAssertEqual(verdict(.ready), .lock)
        XCTAssertEqual(verdict(.unavailable), .lock, "no network must not mean premium")
    }

    /// The first fetch is waited on, and a wait that runs out ends in the
    /// paywall (whose Try again keeps asking), never in the app.
    func test_theWaitEndsInThePaywallNeverTheApp() {
        XCTAssertEqual(verdict(.loading), .wait)
        XCTAssertEqual(verdict(.loading, expired: true), .lock)
    }

    /// Until StoreKit's on-device record has been read a payer and a
    /// stranger look the same, so nothing is decided, however long it takes.
    func test_anUnreadRecordWaitsWithNoTimeout() {
        for state in [Store.State.loading, .ready, .unavailable] {
            XCTAssertEqual(verdict(state, known: false, expired: true), .wait, "\(state)")
        }
    }

    /// A payer opens the app in every state: online, offline, loading.
    func test_aPayerIsNeverLocked() {
        for state in [Store.State.loading, .ready, .unavailable] {
            for expired in [false, true] {
                XCTAssertEqual(verdict(state, entitled: true, expired: expired), .open, "\(state)")
            }
        }
    }

    /// The side-by-side beta owns no products, so it is the one build left
    /// open without a membership.
    func test_theSideBySideBetaIsNeverLocked() {
        for state in [Store.State.loading, .ready, .unavailable] {
            XCTAssertEqual(verdict(state, known: false, expired: true, beta: true), .open, "\(state)")
        }
        XCTAssertTrue(Monetization.isSideBySideBeta(bundleID: "com.lockout.meditate808.dev"))
        XCTAssertFalse(Monetization.isSideBySideBeta(bundleID: "com.lockout.meditate808"))
        XCTAssertFalse(Monetization.isSideBySideBeta(bundleID: "com.lockout.meditate808.devices"))
        XCTAssertFalse(Monetization.isSideBySideBeta(bundleID: nil))
    }

    /// Exhaustively: without a membership, outside the beta, nothing opens
    /// the app.
    func test_nothingButAMembershipOpensTheApp() {
        for state in [Store.State.loading, .ready, .unavailable] {
            for known in [false, true] {
                for expired in [false, true] {
                    XCTAssertNotEqual(verdict(state, known: known, expired: expired), .open,
                                      "\(state) known:\(known) expired:\(expired)")
                }
            }
        }
    }
}
