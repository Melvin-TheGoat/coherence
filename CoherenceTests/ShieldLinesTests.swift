import XCTest
import UIKit

/// The blocker's lines and colours (Aziz, 2026-10-06).
final class ShieldLinesTests: XCTestCase {
    private func hasEmoji(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000) }
    }

    func test_everyLineCarriesAnEmojiInItsTitle() {
        for line in ShieldLines.all {
            XCTAssertTrue(hasEmoji(line.title), "no emoji: \(line.title)")
        }
    }

    func test_noEmDashesAnywhere() {
        for line in ShieldLines.all {
            XCTAssertFalse(line.title.contains("\u{2014}") || line.subtitle.contains("\u{2014}"), line.title)
        }
    }

    func test_theAppNameFillsInAndOpensASentenceCapitalised() {
        let wait = ShieldLines.all.first { $0.title.hasPrefix("{app}") }!
        XCTAssertEqual(ShieldLines.fill(wait.title, app: "TikTok"), "TikTok can wait 🧘")
        XCTAssertEqual(ShieldLines.fill(wait.title, app: nil), "This app can wait 🧘")
        XCTAssertEqual(ShieldLines.fill("Otto's holding {app} for you 🔒", app: "Instagram"),
                       "Otto's holding Instagram for you 🔒")
        for line in ShieldLines.all {
            XCTAssertFalse(ShieldLines.fill(line.title, app: "X").contains("{"), line.title)
            XCTAssertFalse(ShieldLines.fill(line.subtitle, app: "X").contains("{"), line.subtitle)
        }
    }

    func test_aNewPickNeverRepeatsTheLineOrColourJustShown() {
        for line in 0..<ShieldLines.all.count {
            for palette in 0..<ShieldLines.palettes.count {
                for r in 0..<12 {
                    let next = ShieldLines.next(after: (line, palette), random: { min(r, $0 - 1) })
                    XCTAssertNotEqual(next.line, line)
                    XCTAssertNotEqual(next.palette, palette)
                    XCTAssertTrue((0..<ShieldLines.all.count).contains(next.line))
                    XCTAssertTrue((0..<ShieldLines.palettes.count).contains(next.palette))
                }
            }
        }
    }

    func test_thereAreThirteenLinesAndTenColours() {
        XCTAssertEqual(ShieldLines.all.count, 13)
        XCTAssertEqual(ShieldLines.palettes.count, 10)
    }
}

extension ShieldLinesTests {
    func test_eachLineHasItsOwnOtto() {
        let icons = ShieldLines.all.map(ShieldLines.icon)
        XCTAssertEqual(Set(icons).count, ShieldLines.all.count)
        XCTAssertEqual(icons.first, "ShieldOtto1")
        XCTAssertEqual(icons.last, "ShieldOtto13")
        for name in icons { XCTAssertNotNil(UIImage(named: name), "missing \(name)") }
    }
}

/// Every shield stays readable on a phone (2026-10-07). iOS 26 draws the
/// primary button as Liquid Glass and rewrites its label: mixed with half the
/// fill, toward white (label + fill / 2) or toward black
/// (label - (1 - fill) / 2), depending on the phone's appearance and what is
/// behind the glass. Measured from Apple's own shield controller in the
/// simulator (`ShieldRealHarness`) to within a level per channel. A pair has
/// to read in all three cases, because which one a phone picks is not ours to
/// choose.
extension ShieldLinesTests {
    private typealias RGB = (Double, Double, Double)

    private func rgb(_ hex: UInt32) -> RGB {
        (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
    }

    private func luminance(_ c: RGB) -> Double {
        func lin(_ v: Double) -> Double {
            let s = min(255, max(0, v)) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func glassLabels(_ label: UInt32, on fill: UInt32) -> [(String, RGB)] {
        let l = rgb(label), f = rgb(fill)
        func each(_ op: (Double, Double) -> Double) -> RGB {
            (min(255, max(0, op(l.0, f.0))), min(255, max(0, op(l.1, f.1))), min(255, max(0, op(l.2, f.2))))
        }
        return [("as set", l),
                ("lifted", each { $0 + $1 / 2 }),
                ("pushed down", each { $0 - (255 - $1) / 2 })]
    }

    func test_everyButtonLabelReadsWhicheverWayIOSRewritesIt() {
        for (i, p) in ShieldLines.palettes.enumerated() {
            for (name, label) in glassLabels(p.buttonText, on: p.button) {
                XCTAssertGreaterThanOrEqual(contrast(label, rgb(p.button)), 4.5,
                                            "colour \(i), label \(name)")
            }
        }
    }

    /// The pair Melvin reported (2026-10-07): a dark label on a gold button
    /// reads 2.2:1 once iOS lifts it. The check above would have caught it.
    func test_theOldGoldButtonFailsTheCheck() {
        let lifted = glassLabels(0x2B2117, on: 0xF0C47B)[1].1
        XCTAssertLessThan(contrast(lifted, rgb(0xF0C47B)), 3)
    }

    func test_titleAndSubtitleReadOnTheirBackground() {
        for (i, p) in ShieldLines.palettes.enumerated() {
            let bg = rgb(p.background)
            XCTAssertGreaterThanOrEqual(contrast(rgb(p.text), bg), 4.5, "colour \(i) title")
            let s = rgb(p.soft), a = p.softAlpha
            let subtitle: RGB = (s.0 * a + bg.0 * (1 - a), s.1 * a + bg.1 * (1 - a), s.2 * a + bg.2 * (1 - a))
            XCTAssertGreaterThanOrEqual(contrast(subtitle, bg), 4.5, "colour \(i) subtitle")
        }
    }

    /// `paint` under `material` draws `background`, where the material has a
    /// formula (deep purple's is measured only). If one is edited without the
    /// other, the shield stops looking like its palette.
    func test_eachPaintDrawsItsBackground() {
        for (i, p) in ShieldLines.palettes.enumerated() {
            guard let drawn = p.material.render(p.paint) else { continue }
            let want = rgb(p.background)
            for (got, w) in [(drawn.r, want.0), (drawn.g, want.1), (drawn.b, want.2)] {
                XCTAssertLessThanOrEqual(abs(got - w), 3, "colour \(i)")
            }
        }
    }
}
