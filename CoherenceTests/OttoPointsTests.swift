import XCTest

/// Points for the shop: one per minute meditated, never a stored balance.
/// `OttoPoints` and `HatCatalog` are pure `Shared/` types, so this needs no
/// `@testable import` (the test target compiles `Shared/` into itself).
final class OttoPointsTests: XCTestCase {

    private func session(minutes: Int, logged: Bool = false) -> Session {
        Session(startedAt: Date(), durationSec: minutes * 60,
                source: logged ? "logged" : "watch")
    }

    // MARK: earned

    func test_loggedSessionsEarnNothing() {
        let sessions = [session(minutes: 20), session(minutes: 45, logged: true)]
        XCTAssertEqual(OttoPoints.earned(sessions: sessions), 20,
                       "a hand-logged session has no instrument behind it and must not pay out")
    }

    func test_earnedSumsEveryNonLoggedSession() {
        let sessions = [session(minutes: 10), session(minutes: 5), session(minutes: 25)]
        XCTAssertEqual(OttoPoints.earned(sessions: sessions), 40)
    }

    /// `durationSec / 60` floors: a session short of a full minute buys
    /// nothing extra, and a session that is not quite two minutes reads one.
    func test_roundingDownToTheWholeMinute() {
        XCTAssertEqual(OttoPoints.earned(sessions: [Session(startedAt: Date(), durationSec: 59)]), 0)
        XCTAssertEqual(OttoPoints.earned(sessions: [Session(startedAt: Date(), durationSec: 60)]), 1)
        XCTAssertEqual(OttoPoints.earned(sessions: [Session(startedAt: Date(), durationSec: 119)]), 1)
        XCTAssertEqual(OttoPoints.earned(sessions: [Session(startedAt: Date(), durationSec: 120)]), 2)
    }

    // MARK: spent / balance

    func test_spentSubtractsOwnedHatsFromTheBalance() {
        let sessions = [session(minutes: 200)]
        XCTAssertEqual(OttoPoints.spent(ownedHatIDs: []), 0)
        XCTAssertEqual(OttoPoints.spent(ownedHatIDs: ["beanie"]), HatCatalog.item("beanie")!.price)
        let owned = ["beanie", "sunhat"]
        let expectedSpent = HatCatalog.item("beanie")!.price + HatCatalog.item("sunhat")!.price
        XCTAssertEqual(OttoPoints.spent(ownedHatIDs: owned), expectedSpent)
        XCTAssertEqual(OttoPoints.balance(sessions: sessions, ownedHatIDs: owned),
                       200 - expectedSpent)
    }

    func test_balanceNeverGoesNegative() {
        // A catalog change could in principle make spent exceed earned;
        // the shop must never show a negative number for it.
        let sessions = [session(minutes: 5)]
        XCTAssertEqual(OttoPoints.balance(sessions: sessions, ownedHatIDs: ["goldcrown"]), 0)
    }

    /// **A price change to the catalog cannot make an owned hat unowned.**
    /// Ownership is membership in the caller's own `ownedHatIDs` list, never
    /// a catalog lookup a later edit can undo.
    func test_aPriceChangeCannotUnownAHat() {
        let originalCatalog = [HatCatalog.Item(id: "beanie", name: "Beanie", price: 20)]
        let repricedCatalog = [HatCatalog.Item(id: "beanie", name: "Beanie", price: 999)]
        let removedCatalog: [HatCatalog.Item] = []

        // Bought at 20, against a balance that only ever covers 20.
        let sessions = [session(minutes: 20)]
        XCTAssertEqual(OttoPoints.balance(sessions: sessions, ownedHatIDs: [], catalog: originalCatalog), 20,
                       "affordable before the purchase")

        // The catalog reprices it far out of reach after the fact.
        let stillOwned = ["beanie"]
        XCTAssertTrue(stillOwned.contains("beanie"), "ownership is the id list, unaffected by any catalog")
        // Spending now reads the NEW price, which can push balance to zero,
        // but it never claims the hat itself was returned or revoked.
        XCTAssertEqual(OttoPoints.balance(sessions: sessions, ownedHatIDs: stillOwned, catalog: repricedCatalog), 0)

        // Removed from the catalog entirely: nothing left to charge for it,
        // and it is still owned.
        XCTAssertEqual(OttoPoints.spent(ownedHatIDs: stillOwned, catalog: removedCatalog), 0)
        XCTAssertEqual(OttoPoints.balance(sessions: sessions, ownedHatIDs: stillOwned, catalog: removedCatalog), 20)
    }
}
