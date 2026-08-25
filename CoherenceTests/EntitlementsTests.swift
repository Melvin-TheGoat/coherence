import XCTest
@testable import Coherence

/// The free tier decides what every screen shows, so its one rule is asserted
/// rather than trusted to review.
final class EntitlementsTests: XCTestCase {

    /// **The inversion that protects the beta and every offline payer.**
    ///
    /// Free is the floor, but a user we cannot CLASSIFY is not a free user.
    /// While the store cannot sell, everyone is treated as paid. Simplifying
    /// this to `entitled` alone would strip every beta tester of their curves
    /// the moment products go live, before anyone had a chance to buy, and
    /// would downgrade a paying user whose network dropped at the wrong moment.
    func test_cannotSellMeansEverythingUnlocked() {
        for state in [Store.State.loading, .unavailable] {
            XCTAssertTrue(Entitlements.resolve(state: state, entitled: false).paid,
                          "\(state) must not lock anyone out")
            XCTAssertTrue(Entitlements.resolve(state: state, entitled: true).paid)
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
