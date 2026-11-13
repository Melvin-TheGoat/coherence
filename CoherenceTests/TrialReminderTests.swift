import XCTest

/// Otto's "your free trial ends tomorrow" reminder, which onboarding promises
/// before the paywall (2026-11-11). Every rule here is about the reminder
/// arriving in time to be USED: Apple only stops a renewal cancelled at least
/// 24 hours before the period ends.
final class TrialReminderTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// The mockup's case: a 7-day trial started Wednesday Nov 11 at 9 PM
    /// ends Wednesday Nov 18 at 9 PM, and Otto reminds them Tuesday morning.
    func test_aSevenDayTrialIsRemindedTheMorningBefore() {
        let start = date(2026, 11, 11, 21)
        let t = TrialReminder.timeline(start: start, days: 7, calendar: cal)
        XCTAssertEqual(t.end, date(2026, 11, 18, 21))
        XCTAssertEqual(t.reminder, date(2026, 11, 17, 10))
        XCTAssertEqual(TrialReminder.endsWhen(fire: t.reminder, end: t.end, calendar: cal), "tomorrow")
        XCTAssertEqual(TrialReminder.body(fire: t.reminder, end: t.end, calendar: cal),
                       "Your free trial ends tomorrow. Want to keep meditating together?")
    }

    /// A trial ending in the small hours would leave the morning before with
    /// under 24 hours to cancel, so the reminder comes a day earlier and says
    /// which day it ends rather than "tomorrow".
    func test_aTrialEndingAtNightIsRemindedADayEarlier() {
        let end = date(2026, 11, 18, 2)
        let fire = TrialReminder.fireDate(trialEnd: end, now: date(2026, 11, 11, 2), calendar: cal)
        XCTAssertEqual(fire, date(2026, 11, 16, 10))
        XCTAssertEqual(TrialReminder.endsWhen(fire: fire!, end: end, calendar: cal), "on Wednesday")
    }

    /// Whatever hour the trial started, the reminder lands in the morning and
    /// leaves at least 26 hours to cancel.
    func test_everyStartLeavesTimeToCancelAndNeverFiresAtNight() {
        for hour in 0..<24 {
            for minute in [0, 29, 59] {
                let start = date(2026, 11, 11, hour, minute)
                for days in [3, 7] {
                    let end = TrialReminder.end(start: start, days: days, calendar: cal)
                    guard let fire = TrialReminder.fireDate(trialEnd: end, now: start, calendar: cal) else {
                        return XCTFail("no reminder for a \(days)-day trial from \(hour):\(minute)")
                    }
                    XCTAssertGreaterThanOrEqual(end.timeIntervalSince(fire), TrialReminder.minimumLead)
                    XCTAssertEqual(cal.component(.hour, from: fire), TrialReminder.hour)
                    XCTAssertLessThan(end.timeIntervalSince(fire), 3 * 86_400, "not absurdly early either")
                }
            }
        }
    }

    /// A reminder whose moment has passed is never sent late.
    func test_aReminderThatHasPassedIsNotScheduled() {
        let end = date(2026, 11, 18, 21)
        XCTAssertNil(TrialReminder.fireDate(trialEnd: end, now: date(2026, 11, 17, 11), calendar: cal))
        XCTAssertNotNil(TrialReminder.fireDate(trialEnd: end, now: date(2026, 11, 17, 9), calendar: cal))
    }

    /// The App Store counts a trial in calendar days, so it ends at the same
    /// time of day, across a change of the clocks too (Nov 1, 2026, in New York).
    func test_theTrialEndsAtTheSameTimeOfDay() {
        let start = date(2026, 10, 29, 20, 15)
        XCTAssertEqual(TrialReminder.end(start: start, days: 7, calendar: cal), date(2026, 11, 5, 20, 15))
    }

    /// The words carry no em dash (the house rule for anything a person reads).
    func test_theWordsHaveNoEmDash() {
        let t = TrialReminder.timeline(start: date(2026, 11, 11, 21), days: 7, calendar: cal)
        XCTAssertFalse(TrialReminder.body(fire: t.reminder, end: t.end, calendar: cal).contains("\u{2014}"))
    }
}
