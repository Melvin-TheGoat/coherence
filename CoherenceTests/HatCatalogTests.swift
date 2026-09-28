import XCTest

/// The hat list itself: unique ids, and prices that only ever go up down
/// the list, so `ShopTab`'s grid and `OttoPoints` never have to sort it.
final class HatCatalogTests: XCTestCase {

    func test_idsAreUnique() {
        let ids = HatCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "every hat needs its own id")
    }

    func test_pricesAscend() {
        let prices = HatCatalog.all.map(\.price)
        XCTAssertEqual(prices, prices.sorted(), "the list is already in cheapest-first order")
        XCTAssertEqual(Set(prices).count, prices.count, "no two hats tie on price")
    }

    /// The spread the shop was asked for: the first hat within a couple of
    /// short sessions, the last a standing practice.
    func test_priceSpreadMatchesTheBrief() {
        XCTAssertLessThanOrEqual(HatCatalog.all.first!.price, 25)
        XCTAssertGreaterThanOrEqual(HatCatalog.all.last!.price, 800)
    }

    func test_itemLooksUpByID() {
        XCTAssertEqual(HatCatalog.item("beanie")?.id, "beanie")
        XCTAssertNil(HatCatalog.item("not-a-real-hat"))
    }
}
