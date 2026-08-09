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
    /// A zero in the breathing series means the window could not be read, not
    /// that breathing stopped. Plotting it drew the line down to the floor and
    /// invented a collapse, and it dragged the chart's y-axis down with it so
    /// the real curve was squashed into the top. Unreadable windows are simply
    /// not plotted, and the surviving points keep their true timestamps so the
    /// chart joins across the gap.
    func test_unreadableBreathingWindowsAreNotPlottedAsZero() {
        let breathing = [6.0, 6.2, 0, 0, 0, 6.4, 6.1]      // a gap in the middle
        let series = SessionEvidence.series(heartRate: [], stillness: [],
                                            breathing: breathing,
                                            windowSec: 30, hopSec: 5)
        let breath = series.first { $0.kind == .breathing }
        XCTAssertNotNil(breath)
        XCTAssertEqual(breath?.points.count, 4, "only the readable windows are plotted")
        XCTAssertFalse(breath?.points.contains { $0.value == 0 } ?? true)

        // timestamps must still be the original window centres, so the line
        // spans the gap rather than closing it up
        XCTAssertEqual(breath?.points.map(\.t), [15, 20, 40, 45])
    }

    /// A session where nothing was readable produces no breathing series at
    /// all, rather than an empty chart frame.
    func test_allZeroBreathingProducesNoSeries() {
        let series = SessionEvidence.series(heartRate: [], stillness: [],
                                            breathing: [0, 0, 0],
                                            windowSec: 30, hopSec: 5)
        XCTAssertNil(series.first { $0.kind == .breathing })
    }

    func test_emptyProducesNoSeries() {
        let s = SessionEvidence.series(
            heartRate: [], stillness: [], breathing: [], windowSec: 30, hopSec: 5)
        XCTAssertTrue(s.isEmpty)
    }
}
