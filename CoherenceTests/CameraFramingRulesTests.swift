#if DEBUG
import XCTest
@testable import Coherence

/// The two decisions the Begin sheet's framing makes without a camera in the
/// room: when the outline says "in frame", and what box the recorder fixes
/// as its region of interest from the preview when the Watch starts.
final class CameraFramingRulesTests: XCTestCase {

    // MARK: "You're in frame": three hits in the last four detections

    func test_threeStraightHitsFrameYouBeforeFourDetectionsExist() {
        XCTAssertTrue(CameraSignalRecorder.isFramed([true, true, true]))
        XCTAssertFalse(CameraSignalRecorder.isFramed([true, true]))
        XCTAssertFalse(CameraSignalRecorder.isFramed([]))
    }

    func test_oneMissedDetectionDoesNotFlickerTheOutline() {
        XCTAssertTrue(CameraSignalRecorder.isFramed([true, true, false, true]))
        XCTAssertTrue(CameraSignalRecorder.isFramed([false, true, true, true]))
    }

    func test_twoMissesInFourIsNotFramed() {
        XCTAssertFalse(CameraSignalRecorder.isFramed([true, false, true, false]))
    }

    func test_onlyTheLastFourCount() {
        // Framed for a while, then walked away: the old hits must not linger.
        XCTAssertFalse(CameraSignalRecorder.isFramed([true, true, true, true, false, false, false, true]))
    }

    // MARK: The ROI fixed from the preview

    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    func test_flipsVisionsBottomLeftOriginAndPadsTwelvePercent() {
        let b = box(0.3, 0.2, 0.4, 0.5)
        let roi = CameraSignalRecorder.medianROI([b, b, b], minimum: 3)
        XCTAssertNotNil(roi)
        // Top-left y = 1 - (0.2 + 0.5) = 0.3, then padded by 12 % of each side.
        XCTAssertEqual(roi!.x, 0.3 - 0.4 * 0.12, accuracy: 1e-9)
        XCTAssertEqual(roi!.y, 0.3 - 0.5 * 0.12, accuracy: 1e-9)
        XCTAssertEqual(roi!.w, 0.4 * 1.24, accuracy: 1e-9)
        XCTAssertEqual(roi!.h, 0.5 * 1.24, accuracy: 1e-9)
    }

    func test_tooFewBoxesFixNothing() {
        let b = box(0.3, 0.2, 0.4, 0.5)
        XCTAssertNil(CameraSignalRecorder.medianROI([b, b], minimum: 3))
        XCTAssertNil(CameraSignalRecorder.medianROI([], minimum: 0))
    }

    func test_oneWildDetectionIsOutvotedByTheMedian() {
        let steady = box(0.3, 0.2, 0.4, 0.5)
        let wild = box(0.0, 0.0, 1.0, 1.0)
        let fromSteady = CameraSignalRecorder.medianROI([steady, steady, steady], minimum: 3)
        let withWild = CameraSignalRecorder.medianROI([steady, wild, steady], minimum: 3)
        XCTAssertEqual(withWild, fromSteady)
    }
}
#endif
