import XCTest
import SwiftUI
@testable import Coherence

/// The system `Slider` on the session's page only tracked a drag that began
/// exactly on its thumb, so a tap elsewhere on the track (or a drag started
/// elsewhere) did nothing at all (Melvin: "doesn't work at all"). It was
/// replaced with `RatingSlider`, whose own `DragGesture(minimumDistance: 0)`
/// needs a live touch to exercise, but the position-to-value arithmetic it
/// writes the `rating` binding through is a pure function. These lock that
/// function: the touch that lands at the left edge reads the lowest value,
/// the touch at the right edge reads the highest, a touch in between reads
/// the value whose own position it is, and a touch off either end clamps
/// rather than producing an out-of-range or garbage rating.
final class RatingSliderMathTests: XCTestCase {
    private let width: CGFloat = 300
    private let thumb: CGFloat = 26
    private let range = 0...10

    func test_leftEdge_readsTheLowestValue() {
        let value = RatingSliderMath.value(atX: 0, width: width, thumbDiameter: thumb, range: range)
        XCTAssertEqual(value, 0)
    }

    func test_rightEdge_readsTheHighestValue() {
        let value = RatingSliderMath.value(atX: width, width: width, thumbDiameter: thumb, range: range)
        XCTAssertEqual(value, 10)
    }

    func test_midpoint_readsTheMiddleValue() {
        let value = RatingSliderMath.value(atX: width / 2, width: width, thumbDiameter: thumb, range: range)
        XCTAssertEqual(value, 5)
    }

    /// A touch anywhere along the track reads back as the value whose own
    /// thumb position it is: the whole point of "follows the finger."
    func test_everyTick_roundTripsThroughItsOwnPosition() {
        let travel = width - thumb
        for tick in range {
            let fraction = CGFloat(tick - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
            let x = thumb / 2 + travel * fraction
            let value = RatingSliderMath.value(atX: x, width: width, thumbDiameter: thumb, range: range)
            XCTAssertEqual(value, tick, "a touch on tick \(tick)'s own position must read back \(tick)")
        }
    }

    /// A tap does not have to land inside the track's own coordinate space
    /// exactly: the control's `contentShape` covers the whole row, so a
    /// touch can arrive slightly negative or past the far edge.
    func test_touchBeyondEitherEdge_clampsInsteadOfGoingOutOfRange() {
        XCTAssertEqual(RatingSliderMath.value(atX: -80, width: width, thumbDiameter: thumb, range: range), 0)
        XCTAssertEqual(RatingSliderMath.value(atX: 5000, width: width, thumbDiameter: thumb, range: range), 10)
    }

    /// A row narrower than the thumb (a collapsed layout pass, or a very
    /// small phone) must not divide by zero or crash; it degrades to the
    /// low end instead.
    func test_widthNarrowerThanTheThumb_doesNotDivideByZero() {
        let value = RatingSliderMath.value(atX: 5, width: 10, thumbDiameter: thumb, range: range)
        XCTAssertEqual(value, 0)
    }

    /// The drag is continuous, not just tick-discrete: small moves inside a
    /// tick's span still resolve to a sane nearby value rather than sticking.
    func test_smallMovesInsideATick_resolveToTheNearestValue() {
        let travel = width - thumb
        let tick6X = thumb / 2 + travel * (6.0 / 10.0)
        let justPast = RatingSliderMath.value(atX: tick6X + 2, width: width, thumbDiameter: thumb, range: range)
        let justBefore = RatingSliderMath.value(atX: tick6X - 2, width: width, thumbDiameter: thumb, range: range)
        XCTAssertEqual(justPast, 6)
        XCTAssertEqual(justBefore, 6)
    }
}
