import XCTest
@testable import Coherence

final class ContentFilterTests: XCTestCase {

    func test_ordinaryMeditationTextPasses() {
        for ok in ["Roof before work. Cold enough to see my breath.",
                   "Hard as hell today, damn restless", "Scunthorpe sunrise sit",
                   "assessing my class schedule", "grapefruit and green tea first",
                   "Evening meditation", "I love this", "@jordan.k", "session 5 of 10",
                   "cocktail party later, needed this", "analysis paralysis gone"] {
            XCTAssertEqual(ContentFilter.check(ok), .ok, ok)
        }
    }

    func test_obviousAbuseIsBlocked() {
        for bad in ["fuck you", "you're a bitch", "kys", "send nudes"] {
            XCTAssertEqual(ContentFilter.check(bad), .blocked, bad)
        }
    }

    func test_disguisedSpellingsAreBlocked() {
        for bad in ["F.U.C.K", "fvck", "f*ck", "fuuuuck", "b1tch", "f u c k", "k y s", "p0rn"] {
            XCTAssertEqual(ContentFilter.check(bad), .blocked, bad)
        }
    }

    func test_anyBlockedFieldBlocksTheWhole() {
        XCTAssertEqual(ContentFilter.check(["Morning sit", "nice", "porn"]), .blocked)
        XCTAssertEqual(ContentFilter.check(["Morning sit", "", "nice"]), .ok)
    }
}
