import XCTest
// SessionCalendar is compiled into this test target via Shared/ (see project.yml).

final class SessionCalendarTests: XCTestCase {

    /// A fixed, deterministic calendar: Gregorian, UTC, weeks start on Sunday.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1   // Sunday
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: practicedDays

    func test_practicedDays_collapsesSameDay() {
        let dates = [date(2026, 7, 20, 8), date(2026, 7, 20, 21), date(2026, 7, 22, 6)]
        let days = SessionCalendar.practicedDays(from: dates, calendar: cal)
        XCTAssertEqual(days.count, 2, "two sessions on Jul 20 collapse to one day")
        XCTAssertTrue(days.contains(cal.startOfDay(for: date(2026, 7, 20))))
        XCTAssertTrue(days.contains(cal.startOfDay(for: date(2026, 7, 22))))
    }

    func test_practicedDays_emptyIsEmpty() {
        XCTAssertTrue(SessionCalendar.practicedDays(from: [], calendar: cal).isEmpty)
    }

    // MARK: monthGrid

    func test_monthGrid_shapeAndAlignment() {
        // July 2026: the 1st is a Wednesday. Sunday-start grid begins on Jun 28.
        let grid = SessionCalendar.monthGrid(containing: date(2026, 7, 15), calendar: cal)

        XCTAssertEqual(grid.count, 6, "always 6 rows")
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 }, "always 7 columns")

        // First cell is the Sunday on/just before the 1st.
        XCTAssertEqual(grid[0][0], cal.startOfDay(for: date(2026, 6, 28)))
        // July 1 lands in the first row (Wed = column 3 with Sunday start).
        XCTAssertEqual(grid[0][3], cal.startOfDay(for: date(2026, 7, 1)))
        // Grid is 42 contiguous days.
        XCTAssertEqual(grid[5][6], cal.startOfDay(for: date(2026, 8, 8)))
    }

    func test_monthGrid_containsEveryDayOfMonth() {
        let grid = SessionCalendar.monthGrid(containing: date(2026, 7, 15), calendar: cal)
        let all = Set(grid.flatMap { $0 })
        for d in 1...31 {
            XCTAssertTrue(all.contains(cal.startOfDay(for: date(2026, 7, d))),
                          "grid must contain Jul \(d)")
        }
    }

    func test_isSameMonth() {
        XCTAssertTrue(SessionCalendar.isSameMonth(date(2026, 7, 1), as: date(2026, 7, 31), calendar: cal))
        XCTAssertFalse(SessionCalendar.isSameMonth(date(2026, 6, 30), as: date(2026, 7, 1), calendar: cal))
    }

    // MARK: weeks
    //
    // The log is read a week at a time, so these pin the two things that
    // would be invisible until somebody's history landed in the wrong week:
    // where a week begins, and that its end is half-open.

    func test_weekStart_isTheCalendarsOwnFirstWeekday() {
        // Sep 2026: the 20th is a Sunday, the 22nd a Tuesday.
        let tue = date(2026, 9, 22)
        XCTAssertEqual(SessionCalendar.weekStart(for: tue, calendar: cal),
                       cal.startOfDay(for: date(2026, 9, 20)))

        var monday = cal
        monday.firstWeekday = 2
        XCTAssertEqual(SessionCalendar.weekStart(for: tue, calendar: monday),
                       monday.startOfDay(for: date(2026, 9, 21)),
                       "a Monday-first locale must not borrow Sunday's week")
    }

    func test_weekStart_onTheFirstDayIsThatDay() {
        let sunday = date(2026, 9, 20, 23)
        XCTAssertEqual(SessionCalendar.weekStart(for: sunday, calendar: cal),
                       cal.startOfDay(for: date(2026, 9, 20)))
    }

    func test_week_isSevenDaysFromItsStart() {
        let week = SessionCalendar.week(containing: date(2026, 9, 22), calendar: cal)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first, cal.startOfDay(for: date(2026, 9, 20)))
        XCTAssertEqual(week.last, cal.startOfDay(for: date(2026, 9, 26)))
    }

    func test_weekStepping_crossesAMonthBoundary() {
        let start = SessionCalendar.weekStart(for: date(2026, 9, 3), calendar: cal)
        XCTAssertEqual(SessionCalendar.week(-1, from: start, calendar: cal),
                       cal.startOfDay(for: date(2026, 8, 23)))
        XCTAssertEqual(SessionCalendar.week(1, from: start, calendar: cal),
                       cal.startOfDay(for: date(2026, 9, 6)))
    }

    /// **Half-open, and this is the one that matters.** A session at
    /// 23:59:59 on the last day of a week and one at 00:00:00 on the next
    /// week's first day are a second apart and belong to different weeks; an
    /// inclusive end built from midnight would file both under the earlier.
    func test_isIn_week_isHalfOpen() {
        let start = SessionCalendar.weekStart(for: date(2026, 9, 22), calendar: cal)
        XCTAssertTrue(SessionCalendar.isIn(week: start, date(2026, 9, 20, 0), calendar: cal))
        XCTAssertTrue(SessionCalendar.isIn(week: start, date(2026, 9, 26, 23), calendar: cal))
        XCTAssertFalse(SessionCalendar.isIn(week: start, date(2026, 9, 27, 0), calendar: cal),
                       "the next week's first midnight is NOT in this week")
        XCTAssertFalse(SessionCalendar.isIn(week: start, date(2026, 9, 19, 23), calendar: cal))
    }

    func test_weekTitle_namesTheNearWeeksAndDatesTheRest() {
        let now = date(2026, 9, 22)
        let this = SessionCalendar.weekStart(for: now, calendar: cal)
        XCTAssertEqual(SessionCalendar.weekTitle(this, now: now, calendar: cal), "This week")
        XCTAssertEqual(SessionCalendar.weekTitle(SessionCalendar.week(-1, from: now, calendar: cal),
                                                 now: now, calendar: cal), "Last week")
        // Inside one month the month is named once, and across two it is
        // named twice, so a week is never read as "Aug 30 to 5".
        XCTAssertEqual(SessionCalendar.weekTitle(cal.startOfDay(for: date(2026, 9, 6)),
                                                 now: now, calendar: cal), "Sep 6 to 12")
        XCTAssertEqual(SessionCalendar.weekTitle(cal.startOfDay(for: date(2026, 8, 30)),
                                                 now: now, calendar: cal), "Aug 30 to Sep 5")
    }

    func test_weekTitle_carriesTheYearOnlyWhenItIsNotThisOne() {
        let now = date(2026, 9, 22)
        let title = SessionCalendar.weekTitle(cal.startOfDay(for: date(2025, 9, 7)),
                                              now: now, calendar: cal)
        XCTAssertTrue(title.contains("2025"), "got \(title)")
    }

    /// The picker selects a ROW of `monthGrid`, so a row must be exactly the
    /// week the log then shows. If these two ever disagree, tapping a row
    /// lands the reader on a different seven days than the one they touched.
    func test_monthGridRowsAreWeeks() {
        for row in SessionCalendar.monthGrid(containing: date(2026, 9, 22), calendar: cal) {
            XCTAssertEqual(row.first, SessionCalendar.weekStart(for: row[0], calendar: cal))
            XCTAssertEqual(SessionCalendar.week(containing: row[3], calendar: cal), row)
        }
    }
}
