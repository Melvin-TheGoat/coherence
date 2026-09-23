import XCTest
@testable import Coherence

/// The onboarding tour: Otto walking the reader through the real app
/// (Melvin, 2026-09-22: "quickly show the user the different screens, quickly
/// being the name of the game, dont want to waste time").
final class TourStopTests: XCTestCase {

    /// Every combination of the two switches a build can ship with.
    private let builds: [(block: Bool, friends: Bool)] = [
        (true, true), (true, false), (false, true), (false, false),
    ]

    private var everyLine: [String] {
        builds.flatMap { TourStop.all(block: $0.block, friends: $0.friends).map(\.line) }
    }

    func test_tour_isFourToSixStopsOnEveryBuild() {
        for build in builds {
            let count = TourStop.all(block: build.block, friends: build.friends).count
            XCTAssertTrue((4...6).contains(count), "\(build): \(count) stops")
        }
    }

    /// Finishing lands on Home, so the tour ends there, on the plus: the dim
    /// lifts off the screen the reader is about to use.
    func test_tour_startsOnHomeAndEndsOnThePlus() {
        for build in builds {
            let stops = TourStop.all(block: build.block, friends: build.friends)
            XCTAssertEqual(stops.first?.tab, .home)
            XCTAssertEqual(stops.last?.tab, .home)
            XCTAssertEqual(stops.last?.targets, [.begin])
        }
    }

    /// A switched-off feature has no tab to show and no anchor to light.
    func test_tour_visitsATabOnlyWhenItsFeatureIsOn() {
        for build in builds {
            let tabs = TourStop.all(block: build.block, friends: build.friends).map(\.tab)
            XCTAssertEqual(tabs.contains(.block), build.block, "\(build)")
            XCTAssertEqual(tabs.contains(.friends), build.friends, "\(build)")
            XCTAssertTrue(tabs.contains(.profile))
            XCTAssertFalse(tabs.contains(.guide), "the guide is shown on Home, under the streak")
        }
    }

    func test_tour_everyStopLightsSomething() {
        for build in builds {
            for stop in TourStop.all(block: build.block, friends: build.friends) {
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
