import XCTest
import SwiftUI
@testable import Coherence

/// The framing outline is a Shape, not an image: it must fit any rect it is
/// given, keep the front camera's 3:4 proportions inside it, and scale
/// linearly, so the same figure reads the same over a big preview on the
/// Begin sheet and a thumbnail on the live screen.
final class SeatedFigureOutlineTests: XCTestCase {

    private func bounds(_ rect: CGRect) -> CGRect {
        SeatedFigureOutline().path(in: rect).boundingRect
    }

    func test_drawsSomething() {
        XCTAssertFalse(SeatedFigureOutline().path(in: CGRect(x: 0, y: 0, width: 300, height: 400)).isEmpty)
    }

    func test_fitsInsideAnyRect() {
        for rect in [CGRect(x: 0, y: 0, width: 300, height: 400),
                     CGRect(x: 10, y: 20, width: 500, height: 500),
                     CGRect(x: 0, y: 0, width: 96, height: 128),
                     CGRect(x: 0, y: 0, width: 800, height: 200)] {
            let b = bounds(rect)
            XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(b), "figure escaped \(rect): \(b)")
        }
    }

    func test_keepsItsProportionsWhateverTheRect() {
        let design = bounds(CGRect(x: 0, y: 0, width: 300, height: 400))
        let designRatio = design.width / design.height
        for rect in [CGRect(x: 0, y: 0, width: 500, height: 500),
                     CGRect(x: 0, y: 0, width: 800, height: 200),
                     CGRect(x: 0, y: 0, width: 96, height: 128)] {
            let b = bounds(rect)
            XCTAssertEqual(b.width / b.height, designRatio, accuracy: 0.01, "distorted in \(rect)")
        }
    }

    func test_scalesLinearlyAndStaysCentred() {
        let small = bounds(CGRect(x: 0, y: 0, width: 150, height: 200))
        let large = bounds(CGRect(x: 0, y: 0, width: 300, height: 400))
        XCTAssertEqual(large.width, small.width * 2, accuracy: 0.01)
        XCTAssertEqual(large.height, small.height * 2, accuracy: 0.01)

        // The figure is left-right symmetric, so its centre line is the
        // rect's. Vertically the DESIGN BOX is centred, not the figure: the
        // head sits nearer the box's top than the lap does its bottom, on
        // purpose, so the same offset must hold at any scale.
        let rect = CGRect(x: 40, y: 60, width: 500, height: 300)
        let b = bounds(rect)
        XCTAssertEqual(b.midX, rect.midX, accuracy: 0.5)
        let designTopGap = bounds(CGRect(x: 0, y: 0, width: 300, height: 400)).minY / 400
        let scale = min(rect.width / 300, rect.height / 400)
        let boxTop = rect.midY - 400 * scale / 2
        XCTAssertEqual((b.minY - boxTop) / (400 * scale), designTopGap, accuracy: 0.001)
    }
}
