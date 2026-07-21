import SwiftUI
import SwiftData

/// Practice **calendar** page: current/longest streak, total sessions, and a month
/// calendar dotted on the days you practiced. Tapping a practiced day pushes that
/// day's sessions → the per-session graphs (`SessionResultsView`). The full history
/// log lives on its own page (`AllSessionsView`), reached from the home screen.
///
/// Reads storage independently via `@Query`, so it refreshes live when a new
/// session lands from the Watch. Screens pass only IDs/dates; models are immutable.
struct SessionHistoryView: View {
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]

    /// The month currently shown in the calendar (any date within it).
    @State private var monthAnchor = Date()
    /// A practiced day the user tapped — drives the day-detail push.
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    streakHeader
                    calendarSection
                }
                .padding()
            }
            .background(AppColor.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedDay) { day in
                DaySessionsView(day: day)
            }
        }
    }

    // MARK: Streak + count header

    private var streakHeader: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        return HStack(spacing: 12) {
            stat(value: "\(streak.current)", label: "day streak", icon: "flame.fill")
            stat(value: "\(streak.longest)", label: "longest", icon: "trophy.fill")
            stat(value: "\(sessions.count)", label: sessions.count == 1 ? "session" : "sessions",
                 icon: "checkmark.seal.fill")
        }
    }

    private func stat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(AppColor.accentGold)
                .font(.headline)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Calendar

    private var calendarSection: some View {
        let practiced = SessionCalendar.practicedDays(from: sessions.map(\.startedAt), calendar: calendar)
        let grid = SessionCalendar.monthGrid(containing: monthAnchor, calendar: calendar)
        let today = calendar.startOfDay(for: Date())

        return VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle(monthAnchor))
                    .font(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .tint(AppColor.accentGold)

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        let hasSessions = practiced.contains(day)
                        dayCell(day, practiced: hasSessions,
                                inMonth: SessionCalendar.isSameMonth(day, as: monthAnchor, calendar: calendar),
                                isToday: day == today)
                            // Only practiced days are tappable.
                            .contentShape(Rectangle())
                            .onTapGesture { if hasSessions { selectedDay = day } }
                    }
                }
            }
        }
        .padding(16)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func dayCell(_ day: Date, practiced: Bool, inMonth: Bool, isToday: Bool) -> some View {
        let number = calendar.component(.day, from: day)
        return Text("\(number)")
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(practiced ? AppColor.backgroundPrimary
                             : inMonth ? AppColor.textPrimary : AppColor.textSecondary.opacity(0.4))
            .frame(maxWidth: .infinity, minHeight: 34)
            .background {
                if practiced {
                    Circle().fill(AppColor.accentGold).frame(width: 32, height: 32)
                } else if isToday {
                    Circle().stroke(AppColor.accentGold, lineWidth: 1.5).frame(width: 32, height: 32)
                }
            }
    }

    // MARK: Helpers

    private func shiftMonth(_ delta: Int) {
        if let m = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = m
        }
    }

    /// Weekday symbols rotated to start on the calendar's `firstWeekday`.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1        // 0-based
        return Array(symbols[start...] + symbols[..<start])
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }
}

// MARK: - Full history list (its own page)

/// Every session, newest first — the "history" page reached from the overview.
struct AllSessionsView: View {
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var allStats: [MeditationStats]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if sessions.isEmpty {
                    Text("No sessions yet. Start one from the home screen.")
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.vertical, 8)
                } else {
                    let scores = SessionListSupport.scoreMap(allStats)
                    ForEach(sessions) { session in
                        NavigationLink {
                            SessionResultsView(sessionID: session.id)
                        } label: {
                            SessionRow(session: session, score: scores[session.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - One day's sessions (its own page)

/// The sessions started on a single calendar day, reached by tapping a calendar
/// cell. Passed only the day (a Date) and reads storage itself.
struct DaySessionsView: View {
    let day: Date
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var allStats: [MeditationStats]

    private let calendar = Calendar.current

    private var daySessions: [Session] {
        sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let scores = SessionListSupport.scoreMap(allStats)
                ForEach(daySessions) { session in
                    NavigationLink {
                        SessionResultsView(sessionID: session.id)
                    } label: {
                        SessionRow(session: session, score: scores[session.id])
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(SessionListSupport.dayTitle(day))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared row + formatting

/// One tappable session summary row, shared by the full list and the day list.
struct SessionRow: View {
    let session: Session
    let score: Double?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SessionListSupport.rowTime(session.startedAt))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(SessionListSupport.duration(session.durationSec)) · \(session.bellyBreathing ? "belly breathing" : "regular")")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            if let score {
                Text("\(Int((score * 100).rounded()))%")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(AppColor.accentGold)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(14)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Small formatting/lookup helpers shared by the list views.
enum SessionListSupport {
    /// overallScore keyed by sessionID (for the row's at-a-glance %).
    static func scoreMap(_ stats: [MeditationStats]) -> [UUID: Double] {
        var out: [UUID: Double] = [:]
        for s in stats {
            if let sid = s.sessionID, let score = s.overallScore { out[sid] = score }
        }
        return out
    }

    static func rowTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: date)
    }

    static func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    static func duration(_ sec: Int) -> String {
        sec >= 60 ? "\(sec / 60)m \(sec % 60)s" : "\(sec)s"
    }
}
