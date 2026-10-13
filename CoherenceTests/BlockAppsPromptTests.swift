import XCTest
@testable import Coherence

/// Home's one-time "Pick one app for me to hold" (2026-10-13): only for a
/// member with nothing held, and only once, onboarding's ask included.
final class BlockAppsPromptTests: XCTestCase {
    private func blocker(hasApps: Bool) -> Blocker {
        var b = Blocker.preset(.mindfulDay)
        b.hasApps = hasApps
        return b
    }

    func test_asksAMemberWithNothingHeld() {
        XCTAssertTrue(BlockAppsPrompt.shouldAsk(blockers: [blocker(hasApps: false)], asked: false, allowed: true))
        XCTAssertTrue(BlockAppsPrompt.shouldAsk(blockers: [], asked: false, allowed: true))
    }

    func test_neverAsksSomeoneAlreadyHoldingApps() {
        XCTAssertFalse(BlockAppsPrompt.shouldAsk(blockers: [blocker(hasApps: false), blocker(hasApps: true)],
                                                 asked: false, allowed: true))
    }

    func test_asksOnlyOnce() {
        XCTAssertFalse(BlockAppsPrompt.shouldAsk(blockers: [], asked: true, allowed: true))
        let defaults = UserDefaults(suiteName: "BlockAppsPromptTests")!
        defaults.removePersistentDomain(forName: "BlockAppsPromptTests")
        XCTAssertFalse(BlockAppsPrompt.wasAsked(defaults))
        BlockAppsPrompt.markAsked(defaults)
        XCTAssertTrue(BlockAppsPrompt.wasAsked(defaults))
    }

    func test_neverAsksSomeoneBlockIsClosedTo() {
        XCTAssertFalse(BlockAppsPrompt.shouldAsk(blockers: [], asked: false, allowed: false))
    }
}
