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
}
