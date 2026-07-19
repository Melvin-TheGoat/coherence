import XCTest

/// Verifies the evidence-graph data prep: which series appear per session type, and
/// that point timestamps are the window CENTERS on the shared index.
final class SessionEvidenceTests: XCTestCase {

    /// Point i time = i*hopSec + windowSec/2 (window center).
    func test_timestampsAreWindowCenters() {
        let s = SessionEvidence.series(
            heartRate: [70, 68, 66], stillness: [], breathing: [],
            windowSec: 30, hopSec: 5)
        let hr = try? XCTUnwrap(s.first)
        XCTAssertEqual(hr?.points.map(\.t), [15, 20, 25])   // 0*5+15, 1*5+15, 2*5+15
        XCTAssertEqual(hr?.points.map(\.value), [70, 68, 66])
    }

    /// A Regular session (breathing empty) yields exactly heart-rate + stillness.
    func test_regularSessionHasTwoSeries() {
        let s = SessionEvidence.series(
            heartRate: [70, 69], stillness: [0.8, 0.85], breathing: [],
            windowSec: 30, hopSec: 5)
        XCTAssertEqual(s.map(\.kind), [.heartRate, .stillness])
    }

    /// A Belly session (all three populated) yields all three series.
    func test_bellySessionHasThreeSeries() {
        let s = SessionEvidence.series(
            heartRate: [70, 69], stillness: [0.8, 0.85], breathing: [6, 6.2],
            windowSec: 30, hopSec: 5)
        XCTAssertEqual(s.map(\.kind), [.heartRate, .stillness, .breathing])
        XCTAssertEqual(s.last?.unit, "br/min")
    }

    /// No data → no series (nothing to plot).
    func test_emptyProducesNoSeries() {
        let s = SessionEvidence.series(
            heartRate: [], stillness: [], breathing: [], windowSec: 30, hopSec: 5)
        XCTAssertTrue(s.isEmpty)
    }
}
