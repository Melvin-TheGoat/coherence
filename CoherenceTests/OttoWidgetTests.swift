import XCTest

/// The home screen widget (2026-10-05): what the app hands it, worked out by
/// the same rules as Home. A fixed UTC calendar and explicit `now`, as the
/// aura and streak tests do.
final class OttoWidgetTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h))!
    }

    private func sits(_ days: [Int], minutes: Double = 20) -> [OttoAura.Sit] {
        days.map { OttoAura.Sit(date: day($0), seconds: Int(minutes * 60)) }
    }

    /// The widget does not compile `OttoAura`, so it carries its own copy of
    /// the stage bands. They must never disagree, or the drawing on the home
    /// screen would not be the one Home shows.
    func test_widgetStagesMatchTheAura() {
        for level in -5...105 {
            XCTAssertEqual(OttoWidgetSnapshot.stage(level: level), OttoAura.Stage(level: level).rawValue,
                           "level \(level)")
        }
    }

    /// Someone without 808 gets no numbers at all (808 is premium only).
    func test_aNonMemberGetsNoDays() {
        let s = OttoWidgetFeed.snapshot(sits: sits([7, 8, 9]), since: nil, member: false,
                                        now: day(9, 18), calendar: cal)
        XCTAssertFalse(s.member)
        XCTAssertTrue(s.days.isEmpty)
    }

    /// Today is today as it is, and each day after it is how it will stand
    /// at its midnight if nobody meditates: the same glow until the day is
    /// actually missed, then the rest day, then the cost.
    func test_theNextDaysAreProjectedAsIfNobodySits() {
        let s = OttoWidgetFeed.snapshot(sits: sits([7, 8, 9]), since: nil, member: true,
                                        now: day(9, 18), calendar: cal)
        XCTAssertEqual(s.days.count, OttoWidgetFeed.daysAhead + 1)
        XCTAssertEqual(s.days.map(\.start), [9, 10, 11, 12].map { cal.startOfDay(for: day($0)) })

        // Today: three days in, already sat.
        XCTAssertEqual(s.days[0].level, 80)
        XCTAssertEqual(s.days[0].streak, 3)
        XCTAssertEqual(s.days[0].line, "Day 3. You already meditated today, so today is done.")

        // Tomorrow morning: nothing missed yet.
        XCTAssertEqual(s.days[1].level, 80)
        XCTAssertEqual(s.days[1].streak, 3)
        XCTAssertEqual(s.days[1].line, "Day 3. Meditate whenever you're ready, I'll be here.")

        // A day missed: the week's rest day, so nothing lost yet.
        XCTAssertEqual(s.days[2].level, 80)
        XCTAssertEqual(s.days[2].line, "Rest day yesterday. Meditate today and your 3-day streak carries on.")

        // A second day missed costs glow and ends the run.
        XCTAssertLessThan(s.days[3].level, 80)
        XCTAssertEqual(s.days[3].streak, 0)
        XCTAssertEqual(s.days[3].level,
                       OttoAura.level(from: sits([7, 8, 9]), today: cal.startOfDay(for: day(12)), calendar: cal))
    }

    /// The widget shows the latest day that has begun, and the last one
    /// stands once the projection runs out.
    func test_theWidgetPicksTheDayThatHasBegun() {
        let s = OttoWidgetFeed.snapshot(sits: sits([7, 8, 9]), since: nil, member: true,
                                        now: day(9, 18), calendar: cal)
        XCTAssertEqual(s.day(at: day(9, 23))?.start, cal.startOfDay(for: day(9)))
        XCTAssertEqual(s.day(at: cal.startOfDay(for: day(10)))?.start, cal.startOfDay(for: day(10)))
        XCTAssertEqual(s.day(at: day(20))?.start, cal.startOfDay(for: day(12)))
    }

    /// A sad Otto says so; otherwise the line is where today stands, which
    /// is Home's own first line for the day.
    func test_theWidgetLineFollowsHomesRules() {
        let streak = (current: 0, longest: 3, restDayUsed: false)
        XCTAssertEqual(OttoLines.widget(stage: .faded, hasSessions: true, practicedToday: false, streak: streak),
                       "It's been a few days. One short session and I'll be back on my feet.")
        XCTAssertEqual(OttoLines.widget(stage: .withered, hasSessions: true, practicedToday: false, streak: streak),
                       "I've been feeling a bit flat. One session today and I'll perk right up.")
        // A glowing Otto's mood line is Home's, not the widget's: the widget
        // says what today needs.
        let glowing = (current: 6, longest: 6, restDayUsed: false)
        XCTAssertEqual(OttoLines.widget(stage: .radiant, hasSessions: true, practicedToday: true, streak: glowing),
                       "Day 6. You already meditated today, so today is done.")
        XCTAssertEqual(OttoLines.widget(stage: .steady, hasSessions: false, practicedToday: false, streak: streak),
                       "Your first session starts at the plus. I'll be right here.")
        for stage in OttoAura.Stage.allCases where stage > .faded {
            XCTAssertEqual(OttoLines.widget(stage: stage, hasSessions: true, practicedToday: false, streak: streak),
                           OttoLines.today(hasSessions: true, practicedToday: false, streak: streak)[0])
        }
    }

    /// No em dashes in anything Otto says, here as everywhere. And he says
    /// meditate, never sit (Melvin, 2026-10-06).
    func test_ottosLinesHaveNoEmDashesAndSayMeditate() {
        var all: [String] = []
        for stage in OttoAura.Stage.allCases {
            for practiced in [true, false] {
                if let mood = OttoLines.mood(stage, practicedToday: practiced) { all.append(mood) }
            }
        }
        for practiced in [true, false] {
            for streak in [(0, 0, false), (1, 1, false), (3, 3, false), (4, 6, false), (2, 2, true)] {
                all += OttoLines.today(hasSessions: true, practicedToday: practiced,
                                       streak: (current: streak.0, longest: streak.1, restDayUsed: streak.2))
            }
        }
        all += OttoLines.today(hasSessions: false, practicedToday: false, streak: (0, 0, false))
        all.append(OttoLines.widgetNudge)
        // Two lines in Home's bubble on a 375pt phone, the sayings' limit.
        XCTAssertLessThanOrEqual(OttoLines.widgetNudge.count, 74)
        for line in all {
            XCTAssertFalse(line.contains("\u{2014}"), line)
            let words = line.lowercased().split { !$0.isLetter }
            for verb in ["sit", "sat", "sits", "sitting"] {
                XCTAssertFalse(words.contains(Substring(verb)), line)
            }
        }
    }

    /// The app reloads the widget only when what it shows has changed, so
    /// opening 808 often does not spend the widget's refreshes.
    func test_theShelfReportsOnlyRealChanges() throws {
        let suite = "test.widget.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = OttoWidgetFeed.snapshot(sits: sits([7, 8, 9]), since: nil, member: true,
                                            now: day(9, 18), calendar: cal)
        XCTAssertTrue(OttoWidgetShelf.write(first, to: defaults))
        XCTAssertEqual(OttoWidgetShelf.read(from: defaults), first)

        // Written again a minute later: same Otto, no reload.
        var again = first
        again.written = day(9, 19)
        XCTAssertFalse(OttoWidgetShelf.write(again, to: defaults))

        // A session lands: a reload.
        let after = OttoWidgetFeed.snapshot(sits: sits([7, 8, 9, 10]), since: nil, member: true,
                                            now: day(10, 9), calendar: cal)
        XCTAssertTrue(OttoWidgetShelf.write(after, to: defaults))

        // The membership ends: a reload, and no numbers left behind.
        let lapsed = OttoWidgetFeed.snapshot(sits: sits([7, 8, 9, 10]), since: nil, member: false,
                                             now: day(10, 9), calendar: cal)
        XCTAssertTrue(OttoWidgetShelf.write(lapsed, to: defaults))
        XCTAssertEqual(OttoWidgetShelf.read(from: defaults)?.days, [])
    }
}
