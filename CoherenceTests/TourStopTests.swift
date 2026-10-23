import XCTest
@testable import Coherence

/// The onboarding tour: Otto walking the reader through the real app
/// (Melvin, 2026-09-22: "quickly show the user the different screens, quickly
/// being the name of the game, dont want to waste time").
final class TourStopTests: XCTestCase {

    /// Every combination of the two switches a build can ship with.
    private let builds: [(block: Bool, friends: Bool, shop: Bool)] = [
        (true, true, false), (true, false, false), (false, true, false), (false, false, false),
        (true, true, true), (true, false, true), (false, true, true), (false, false, true),
    ]

    private var everyLine: [String] {
        builds.flatMap { TourStop.all(block: $0.block, friends: $0.friends, shop: $0.shop).map(\.line) }
    }

    func test_tour_isFourToSixStopsOnEveryBuild() {
        for build in builds {
            let count = TourStop.all(block: build.block, friends: build.friends, shop: build.shop).count
            XCTAssertTrue((4...6).contains(count), "\(build): \(count) stops")
        }
    }

    /// Finishing lands on Home, so the tour ends there, on the plus: the dim
    /// lifts off the screen the reader is about to use.
    func test_tour_startsOnHomeAndEndsOnThePlus() {
        for build in builds {
            let stops = TourStop.all(block: build.block, friends: build.friends, shop: build.shop)
            XCTAssertEqual(stops.first?.tab, .home)
            XCTAssertEqual(stops.last?.tab, .home)
            XCTAssertEqual(stops.last?.targets, [.begin])
        }
    }

    /// A switched-off feature has no tab to show and no anchor to light.
    func test_tour_visitsATabOnlyWhenItsFeatureIsOn() {
        for build in builds {
            let tabs = TourStop.all(block: build.block, friends: build.friends, shop: build.shop).map(\.tab)
            XCTAssertEqual(tabs.contains(.block), build.block, "\(build)")
            // With the shop on, Friends is a circle on Home and the Store has the tab.
            XCTAssertEqual(tabs.contains(.friends), build.friends && !build.shop, "\(build)")
            XCTAssertEqual(tabs.contains(.store), build.shop, "\(build)")
            let lit = TourStop.all(block: build.block, friends: build.friends, shop: build.shop)
                .flatMap(\.targets)
            XCTAssertEqual(lit.contains(.friendsCircle), build.friends && build.shop, "\(build)")
            XCTAssertTrue(tabs.contains(.profile))
            XCTAssertFalse(tabs.contains(.guide), "the guide is shown on Home, under the streak")
        }
    }

    /// Friends back in the bar and the Shop as Home's corner circle (Melvin,
    /// 2026-10-23): the tour visits the Friends tab, lights the Shop's
    /// circle, and never visits a Store tab that is no longer there.
    func test_tour_withFriendsInTheBar_visitsFriendsAndLightsTheShopCircle() {
        for block in [true, false] {
            let stops = TourStop.all(block: block, friends: true, shop: true, friendsTab: true)
            let tabs = stops.map(\.tab)
            let lit = stops.flatMap(\.targets)
            XCTAssertTrue(tabs.contains(.friends))
            XCTAssertFalse(tabs.contains(.store))
            XCTAssertTrue(lit.contains(.shopCircle))
            XCTAssertFalse(lit.contains(.friendsCircle))
            XCTAssertTrue((4...6).contains(stops.count), "\(stops.count) stops")
            for line in stops.map(\.line) {
                XCTAssertLessThanOrEqual(line.count, 74, line)
                XCTAssertEqual(line.filter { ".!?".contains($0) }.count, 1, "one sentence: \(line)")
            }
        }
        // Friends switched off: the Shop keeps its tab whatever the swap says.
        let noFriends = TourStop.all(block: true, friends: false, shop: true, friendsTab: true).map(\.tab)
        XCTAssertTrue(noFriends.contains(.store))
    }

    func test_tour_everyStopLightsSomething() {
        for build in builds {
            for stop in TourStop.all(block: build.block, friends: build.friends, shop: build.shop) {
                XCTAssertFalse(stop.targets.isEmpty, stop.line)
            }
        }
    }

    /// One short sentence, the same two lines of bubble his sayings get.
    func test_tour_linesAreOneShortSentence() {
        for line in everyLine {
            XCTAssertLessThanOrEqual(line.count, 74, line)
            XCTAssertTrue(line.hasSuffix("."), line)
            XCTAssertEqual(line.filter { ".!?".contains($0) }.count, 1, "one sentence: \(line)")
        }
    }

    func test_tour_linesCarryNoEmDashes() {
        for line in everyLine {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), line)
        }
    }

    /// The same banned list as his sayings, plus thanks: looking after Otto
    /// is not a favour to him, so he never thanks anyone for it.
    func test_tour_linesNeverMentionAScoreADoorwayAWatchOrThanks() {
        for line in everyLine {
            let lower = line.lowercased()
            for banned in ["score", "doorway", "watch", "heart rate", "measure", "thank"] {
                XCTAssertFalse(lower.contains(banned), "\"\(line)\" mentions \(banned)")
            }
        }
    }
}
