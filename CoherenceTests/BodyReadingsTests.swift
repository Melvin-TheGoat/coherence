import XCTest

final class BodyReadingsTests: XCTestCase {
    func test_aSettledSessionReadsPlainly() {
        let r = BodyReadings(score: 0.84, startHR: 74.2, endHR: 62.9, stillness: 0.92,
                             doorwayRate: 5.8, doorwayHeldSec: 190, meanBreathingRate: 9)
        XCTAssertEqual(r.score, 84)
        XCTAssertEqual(r.readings.map(\.value), ["74 → 63 bpm", "Very still", "5.8 a minute"])
        XCTAssertEqual(r.readings.map(\.note), ["Settled 11 beats", "92% still", "Slow for 3 minutes"])
    }

    func test_noBreathReadMeansNoBreathingLine() {
        let r = BodyReadings(score: 0.4, startHR: 70, endHR: 71, stillness: 0.6,
                             doorwayRate: nil, doorwayHeldSec: nil, meanBreathingRate: nil)
        XCTAssertEqual(r.readings.map(\.label), ["Heart rate", "Stillness"])
        XCTAssertEqual(r.readings.first?.note, "Held steady", "a heart that did not fall is described, not scolded")
        XCTAssertEqual(r.readings.last?.value, "Some movement")
    }

    /// A heart that rose is said to have risen, never "held steady".
    func test_aRisingHeartIsSaidPlainly() {
        func note(_ start: Double, _ end: Double) -> String? {
            BodyReadings(score: 0.3, startHR: start, endHR: end, stillness: nil,
                         doorwayRate: nil, doorwayHeldSec: nil, meanBreathingRate: nil).readings.first?.note
        }
        XCTAssertEqual(note(74, 79), "Rose 5 beats")
        XCTAssertEqual(note(70, 72), "Rose 2 beats")
        XCTAssertEqual(note(70, 71), "Held steady")
        XCTAssertEqual(note(71, 70), "Held steady")
        XCTAssertEqual(note(72, 70), "Settled 2 beats")
    }

    func test_noEmDashes() {
        let r = BodyReadings(score: 0.5, startHR: 80, endHR: 70, stillness: 0.3,
                             doorwayRate: nil, doorwayHeldSec: nil, meanBreathingRate: 11)
        for reading in r.readings {
            XCTAssertFalse((reading.label + reading.value + reading.note).contains("\u{2014}"))
        }
    }
}
