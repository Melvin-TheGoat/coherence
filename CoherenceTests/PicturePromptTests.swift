import XCTest
@testable import Coherence

final class PicturePromptTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Detroit")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func test_onlyAProfileWithoutAPictureIsAsked() {
        XCTAssertTrue(PicturePrompt.due(hasPicture: false, never: false, remindAfter: nil))
        XCTAssertFalse(PicturePrompt.due(hasPicture: true, never: false, remindAfter: nil))
    }

    func test_notNowIsNeverAgain() {
        XCTAssertFalse(PicturePrompt.due(hasPicture: false, never: true, remindAfter: nil))
    }

    /// Melvin, 2026-10-19: "Remind me" asks again the next day, from its
    /// first minute, not 24 hours later.
    func test_remindTomorrowWaitsForTheNextCalendarDay() {
        let evening = date(2026, 10, 19, 21, 30)
        let tomorrow = PicturePrompt.tomorrow(after: evening, calendar: calendar)
        XCTAssertEqual(tomorrow, date(2026, 10, 20, 0, 0))
        XCTAssertFalse(PicturePrompt.due(hasPicture: false, never: false, remindAfter: tomorrow,
                                         now: date(2026, 10, 19, 23, 59)))
        XCTAssertTrue(PicturePrompt.due(hasPicture: false, never: false, remindAfter: tomorrow,
                                        now: date(2026, 10, 20, 0, 0)))
    }

    func test_answersAreRememberedAndForgottenOnSignOut() {
        let defaults = UserDefaults(suiteName: "PicturePromptTests-\(UUID().uuidString)")!
        XCTAssertTrue(PicturePrompt.due(hasPicture: false, defaults: defaults))
        PicturePrompt.remindTomorrow(now: Date(), defaults: defaults)
        XCTAssertFalse(PicturePrompt.due(hasPicture: false, defaults: defaults))
        PicturePrompt.neverAgain(defaults: defaults)
        PicturePrompt.forget(defaults: defaults)
        XCTAssertTrue(PicturePrompt.due(hasPicture: false, defaults: defaults))
    }

    /// Every preset ships with its picture, Otto leads, and no two share an id.
    func test_everyPresetHasItsPicture() {
        XCTAssertEqual(AvatarPreset.all.count, 21)
        XCTAssertEqual(AvatarPreset.all.first?.id, "otto")
        XCTAssertEqual(Set(AvatarPreset.all.map(\.id)).count, AvatarPreset.all.count)
        for preset in AvatarPreset.all {
            XCTAssertNotNil(preset.image, "avatar-\(preset.id).jpg is not in the bundle")
        }
    }
}
