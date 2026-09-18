import XCTest
import SwiftUI
@testable import Coherence

/// The drawings are the mockup's SVG, so what is worth locking is the parser
/// that reads it: a wrong command silently draws a different animal.
final class OttoArtTests: XCTestCase {

    func test_parsesTheCommandsTheDrawingsUse() {
        let p = SVGPath("M17 29.2Q22 33.8 27 29.2")
        XCTAssertEqual(p.commands, [.move(CGPoint(x: 17, y: 29.2)),
                                    .quad(to: CGPoint(x: 27, y: 29.2), c: CGPoint(x: 22, y: 33.8))])

        let h = SVGPath("M30.6 39H33.4")
        XCTAssertEqual(h.commands, [.move(CGPoint(x: 30.6, y: 39)),
                                    .line(CGPoint(x: 33.4, y: 39))])

        let c = SVGPath("M92 101C76 106 62 118 58 136C54 150 54 162 58 172")
        XCTAssertEqual(c.commands.count, 3)
        XCTAssertEqual(c.commands.first, .move(CGPoint(x: 92, y: 101)))
        XCTAssertEqual(c.commands.last, .cubic(to: CGPoint(x: 58, y: 172),
                                               c1: CGPoint(x: 54, y: 150),
                                               c2: CGPoint(x: 54, y: 162)))
    }

    /// Negative coordinates run together with the number before them in SVG
    /// ("58-136"), which is the classic way a hand-rolled parser loses a path.
    func test_aMinusStartsANewNumber() {
        let p = SVGPath("M0 0C-4-8 12-16 20 0")
        XCTAssertEqual(p.commands, [.move(.zero),
                                    .cubic(to: CGPoint(x: 20, y: 0),
                                           c1: CGPoint(x: -4, y: -8),
                                           c2: CGPoint(x: 12, y: -16))])
    }

    /// Every string in the art parses, and none of them silently drops to
    /// nothing. A typo in a `d` string would otherwise just draw less sloth.
    func test_everyStrokeInTheArtParses() {
        for d in OttoArt.faceStrokes + OttoArt.sitBody {
            let p = SVGPath(d)
            XCTAssertGreaterThanOrEqual(p.commands.count, 2, "\(d) parsed to \(p.commands.count)")
            XCTAssertEqual(p.commands.first.map { if case .move = $0 { return true } else { return false } }, true,
                           "\(d) does not begin with a move")
        }
    }

    /// The figure's own drawing stays inside its 240 box, so a caller's frame
    /// is the whole picture and nothing clips.
    func test_theSittingFigureStaysInsideItsBox() {
        var path = Path()
        for d in OttoArt.sitBody { SVGPath(d).append(to: &path, .identity) }
        let box = path.boundingRect
        XCTAssertGreaterThanOrEqual(box.minX, 0)
        XCTAssertGreaterThanOrEqual(box.minY, 0)
        XCTAssertLessThanOrEqual(box.maxX, 240)
        XCTAssertLessThanOrEqual(box.maxY, 240)
    }

    /// The right arm is the left one mirrored about the middle of the box.
    /// Drawn by hand as twelve separate paths, so a stray digit is invisible
    /// on screen and obvious here.
    func test_theArmsAreMirrored() {
        func bounds(_ paths: ArraySlice<String>) -> CGRect {
            var path = Path()
            for d in paths { SVGPath(d).append(to: &path, .identity) }
            return path.boundingRect
        }
        let left = bounds(OttoArt.sitBody[0..<6])
        let right = bounds(OttoArt.sitBody[6..<12])
        XCTAssertEqual(left.minX + right.maxX, 240, accuracy: 1.5)
        XCTAssertEqual(left.minY, right.minY, accuracy: 1.5)
        XCTAssertEqual(left.maxY, right.maxY, accuracy: 1.5)
    }
}
