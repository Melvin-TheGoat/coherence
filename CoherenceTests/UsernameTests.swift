import XCTest
@testable import Coherence

final class UsernameTests: XCTestCase {
    func test_lowercasesAndStripsTheAt() {
        XCTAssertEqual(Username.normalize("@Melvin"), "melvin")
    }

    func test_keepsOnlyHandleCharacters() {
        XCTAssertEqual(Username.normalize("mel vin-van.cleave!7_"), "melvinvan.cleave7_")
    }

    func test_clipsToTwentyCharacters() {
        XCTAssertEqual(Username.normalize(String(repeating: "a", count: 30))?.count, 20)
    }

    func test_emptyIsNilNeverEmptyString() {
        XCTAssertNil(Username.normalize(""))
        XCTAssertNil(Username.normalize("   "))
        XCTAssertNil(Username.normalize("@"))
        XCTAssertNil(Username.normalize("!!!"))
    }

    func test_displayAddsTheAt() {
        XCTAssertEqual(Username.display("melvin"), "@melvin")
        XCTAssertNil(Username.display(nil))
        XCTAssertNil(Username.display(""))
    }
}
