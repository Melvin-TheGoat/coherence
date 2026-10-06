import XCTest

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
