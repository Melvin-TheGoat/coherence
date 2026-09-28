import XCTest

/// Buying and wearing a hat (`OttoShop`), against a plain `Preferences`
/// instance — a `@Model` class can be built and mutated directly without a
/// `ModelContext`, the same way `PhoneSessionTests` builds a bare `Session`.
final class OttoShopTests: XCTestCase {

    private func sessions(minutes: Int) -> [Session] {
        [Session(startedAt: Date(), durationSec: minutes * 60)]
    }

    func test_buyingDeductsAndOwns() {
        let prefs = Preferences()
        XCTAssertTrue(OttoShop.buy("beanie", prefs: prefs, sessions: sessions(minutes: 20)))
        XCTAssertEqual(prefs.ownedHatIDList, ["beanie"])
    }

    func test_cannotBuyTheSameHatTwice() {
        let prefs = Preferences()
        let sessions = sessions(minutes: 1000)
        XCTAssertTrue(OttoShop.buy("beanie", prefs: prefs, sessions: sessions))
        XCTAssertFalse(OttoShop.buy("beanie", prefs: prefs, sessions: sessions),
                       "already owned; a second tap must not charge again")
        XCTAssertEqual(prefs.ownedHatIDList, ["beanie"], "owned once, not twice")
    }

    func test_cannotBuyShortOfTheBalance() {
        let prefs = Preferences()
        XCTAssertFalse(OttoShop.buy("goldcrown", prefs: prefs, sessions: sessions(minutes: 5)))
        XCTAssertEqual(prefs.ownedHatIDList, [], "a refused purchase touches nothing")
    }

    func test_unknownHatIDIsRefused() {
        let prefs = Preferences()
        XCTAssertFalse(OttoShop.buy("not-a-real-hat", prefs: prefs, sessions: sessions(minutes: 5000)))
    }

    func test_wearingRequiresOwningIt() {
        let prefs = Preferences()
        XCTAssertFalse(OttoShop.wear("beanie", prefs: prefs), "cannot wear a hat never bought")
        XCTAssertNil(prefs.wornHatIDValue)

        XCTAssertTrue(OttoShop.buy("beanie", prefs: prefs, sessions: sessions(minutes: 30)))
        XCTAssertTrue(OttoShop.wear("beanie", prefs: prefs))
        XCTAssertEqual(prefs.wornHatIDValue, "beanie")
    }

    func test_wearingNilTakesTheHatOff() {
        let prefs = Preferences()
        _ = OttoShop.buy("beanie", prefs: prefs, sessions: sessions(minutes: 30))
        _ = OttoShop.wear("beanie", prefs: prefs)
        XCTAssertTrue(OttoShop.wear(nil, prefs: prefs))
        XCTAssertNil(prefs.wornHatIDValue)
    }
}
